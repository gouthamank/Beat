import Foundation
import MediaPlayer

/// Reloads when the device's music library changes (a Finder sync, songs deleted on the device), the iOS
/// counterpart of the Mac's FSEvents watcher. The Simulator's folder library has no notifications; it's re-read
/// when Beat becomes active and the folder has changed (`libraryStamp`).
@MainActor
final class LibraryWatcher {
    private var observer: NSObjectProtocol?

    /// Nil in the Simulator, where the library is a folder of files.
    init?(onChange: @escaping @MainActor () -> Void) {
        #if targetEnvironment(simulator)
        return nil
        #else
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
        observer = NotificationCenter.default.addObserver(forName: .MPMediaLibraryDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { onChange() }
        }
        #endif
    }

    /// When the library last changed: MediaPlayer's own date on a device, the Documents folder's in the Simulator.
    nonisolated static func libraryStamp() -> Date? {
        #if targetEnvironment(simulator)
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return (try? folder?.resourceValues(forKeys: [.contentModificationDateKey]))??.contentModificationDate
        #else
        return MPMediaLibrary.default().lastModifiedDate
        #endif
    }
}

/// The device's synced library, or in the Simulator, a folder of audio files; a UI test's is a folder of fixture songs.
func makeLibrarySource() -> any LibrarySource {
    if let folder = LaunchOptions.fixtureLibrary { return FolderLibrarySource(folder: folder, makesMusicFolder: false) }
    #if targetEnvironment(simulator)
    return FolderLibrarySource()
    #else
    return MediaLibrarySource()
    #endif
}
