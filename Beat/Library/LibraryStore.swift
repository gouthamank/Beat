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

    let loader = LibraryLoader()

    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var reloadRequested = false
    @ObservationIgnored private var watcher: LibraryWatcher?

    /// Loads the library. Requests that arrive mid-load (the file watcher, the app becoming active)
    /// coalesce into one more load afterwards, so two never run at once.
    func load() async {
        if isLoading {
            reloadRequested = true
            return
        }
        isLoading = true
        defer { isLoading = false }
        repeat {
            reloadRequested = false
            if snapshot.tracks.isEmpty { state = .loading }
            do {
                snapshot = try await loader.load()
                version += 1
                state = .loaded
            } catch {
                state = .failed(error.localizedDescription)
            }
        } while reloadRequested
    }

    /// Reloads when Music writes to its library while Beat is running.
    func startWatching() {
        guard watcher == nil else { return }
        watcher = LibraryWatcher { [weak self] in
            Task { await self?.load() }
        }
    }
}
