import Foundation
import Observation

@MainActor
@Observable
final class LibraryStore {
    enum State: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    private(set) var snapshot = LibrarySnapshot.empty
    private(set) var state: State = .idle
    /// Bumped on every successful load; used as a cache key by derived results.
    private(set) var version = 0

    let loader: any LibrarySource
    /// Where the library saved at the last read lives (`LibraryCache`).
    @ObservationIgnored private let cacheDirectory: URL?
    /// When the library was last written (`LibraryWatcher.libraryStamp`), to skip reads that would find nothing new.
    @ObservationIgnored private let libraryStamp: @Sendable () -> Date?

    /// The defaults are the platform's library; tests pass a stand-in source and their own cache folder.
    init(loader: any LibrarySource = makeLibrarySource(), cacheDirectory: URL? = LibraryCache.directory,
         libraryStamp: @escaping @Sendable () -> Date? = LibraryWatcher.libraryStamp) {
        self.loader = loader
        self.cacheDirectory = cacheDirectory
        self.libraryStamp = libraryStamp
    }

    /// Art whose picture changed in Music between reads (the app forwards it to `ArtworkCache.invalidate`).
    @ObservationIgnored var onArtworkChanged: @MainActor (Set<ArtworkSource>) -> Void = { _ in }
    /// After each read of Music, with what it found (the app prunes saved thumbnails with it).
    @ObservationIgnored var onRead: @MainActor (LibrarySnapshot) -> Void = { _ in }
    /// Music access failed: nothing from the library may stay on screen or on disk.
    @ObservationIgnored var onAccessLost: @MainActor () -> Void = {}

    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var reloadRequested = false
    @ObservationIgnored private var watcher: LibraryWatcher?
    @ObservationIgnored private var triedSavedLibrary = false
    /// When Music's library files were last written, as of the last read; nil before one, or with no bundle found.
    @ObservationIgnored private var readStamp: Date?

    /// Loads the library. Requests that arrive mid-load (the file watcher, the app becoming active)
    /// coalesce into one more load afterwards, so two never run at once. The first shows the library saved at
    /// the last read at once, then reads Music behind it (about 4 s for 20k songs).
    func load() async {
        if isLoading {
            reloadRequested = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        if !triedSavedLibrary {
            triedSavedLibrary = true
            // Asks for MediaPlayer access on iPad and iPhone (nothing to ask on the Mac). Without it, the read
            // below fails and the usual "No Access" state shows.
            _ = await loader.requestAccess()
            if let saved = await LibraryCache.load(from: cacheDirectory) {
                snapshot = saved
                version += 1
                state = .loaded
            }
        }
        repeat {
            reloadRequested = false
            if snapshot.tracks.isEmpty { state = .loading }
            let stamp = libraryStamp()
            do {
                let loaded = try await loader.load()
                readStamp = stamp
                // Nothing changed: keep the snapshot and version, so derived results aren't recomputed.
                if !snapshot.isSameLibrary(tracks: loaded.tracks) {
                    let changedArt = LibrarySnapshot.changedArtwork(old: snapshot, new: loaded)
                    snapshot = loaded
                    version += 1
                    onArtworkChanged(changedArt)
                    let tracks = loaded.tracks, cacheDirectory = cacheDirectory
                    Task.detached(priority: .utility) { await LibraryCache.save(tracks, in: cacheDirectory) }
                }
                onRead(snapshot)
                state = .loaded
            } catch {
                if !snapshot.tracks.isEmpty {
                    snapshot = .empty
                    version += 1
                }
                LibraryCache.remove(from: cacheDirectory)
                onAccessLost()
                state = .failed(error.localizedDescription)
            }
        } while reloadRequested
    }

    /// Reads Music again only if its library has been written since the last read. Coming back to Beat used to
    /// re-read all ~20k songs (about 4 s of work) every time, though usually nothing had changed.
    func reloadIfMusicChanged() async {
        if let readStamp, let now = libraryStamp(), now <= readStamp { return }
        await load()
    }

    /// Reloads when Music writes to its library while Beat is running.
    func startWatching() {
        guard watcher == nil else { return }
        watcher = LibraryWatcher { [weak self] in
            Task { await self?.load() }
        }
    }
}
