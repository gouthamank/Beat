import CoreServices
import Foundation

/// Watches Music's library bundle and asks for a reload after Music writes to it, so edits made in Music
/// show up while Beat stays in front. Music writes `Library.musicdb` in bursts, hence the debounce.
@MainActor
final class LibraryWatcher {
    private var stream: FSEventStreamRef?
    private var pending: Task<Void, Never>?
    private let onChange: @MainActor () -> Void

    /// Nil when no library bundle can be found; the app then reloads only on activation, as before.
    init?(onChange: @escaping @MainActor () -> Void) {
        guard let bundle = Self.libraryBundle() else { return nil }
        self.onChange = onChange

        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, paths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<LibraryWatcher>.fromOpaque(info).takeUnretainedValue()
            let list = (unsafeBitCast(paths, to: NSArray.self) as? [String]) ?? []
            // The stream is scheduled on the main queue (below).
            MainActor.assumeIsolated { watcher.received(list) }
        }
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        guard let stream = FSEventStreamCreate(
            nil, callback, &context, [bundle.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.5, flags
        ) else { return nil }
        FSEventStreamSetDispatchQueue(stream, .main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func received(_ paths: [String]) {
        guard Self.isRelevant(paths: paths) else { return }
        pending?.cancel()
        pending = Task { [onChange] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            onChange()
        }
    }

    /// Whether any path is one of Music's database files, rather than Finder metadata or preferences.
    nonisolated static func isRelevant(paths: [String]) -> Bool {
        paths.contains { path in
            let name = (path as NSString).lastPathComponent
            return name.hasSuffix(".musicdb") || name.hasSuffix(".itdb") || name == "sentinel"
        }
    }

    /// The default library location first, then any `.musiclibrary` bundle in the usual folders.
    nonisolated static func libraryBundle() -> URL? {
        let files = FileManager.default
        let music = files.homeDirectoryForCurrentUser.appendingPathComponent("Music", isDirectory: true)
        let preferred = music.appendingPathComponent("Music/Music Library.musiclibrary", isDirectory: true)
        if files.fileExists(atPath: preferred.path) { return preferred }
        for folder in [music.appendingPathComponent("Music", isDirectory: true), music] {
            let found = (try? files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
                .first { $0.pathExtension == "musiclibrary" }
            if let found { return found }
        }
        return nil
    }
}
