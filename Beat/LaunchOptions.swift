import Foundation

/// How UI tests launch Beat: on a folder of fixture songs (`-BeatFixtureLibrary <folder>`) instead of the real library,
/// built as its own app (the UITest configuration, bundle ID `dev.gouthaman.Beat.uitest`, so its settings and on iOS
/// its whole container are its own), with its files under a temporary home folder in /tmp (`CFFIXED_USER_HOME`, which
/// Foundation's folders follow; settings don't on macOS, hence the bundle ID). A UI test never reads or writes the
/// user's library, pages or settings; a launch that wouldn't be isolated stops before anything is read.
enum LaunchOptions {
    static let fixtureLibraryArgument = "-BeatFixtureLibrary"
    /// Starts as on a first launch: the UI-test app's settings cleared and its files in the home deleted. Left out when
    /// a test relaunches to check what was kept. Given as `-BeatFreshStart YES`: a bare flag with arguments after it
    /// left one over, which AppKit took for a file to open, and Beat made no window.
    static let freshStartArgument = "-BeatFreshStart"
    static let homeVariable = "CFFIXED_USER_HOME"
    static let uiTestBundleSuffix = ".uitest"

    /// Whether this is a UI-test launch: the fixture argument is there, even without its folder (which then stops
    /// Beat rather than quietly reading the real library).
    static let isUITestLaunch = ProcessInfo.processInfo.arguments.contains(fixtureLibraryArgument)

    /// The fixture folder when a UI test launched Beat, else nil.
    static let fixtureLibrary: URL? = fixtureLibrary(in: ProcessInfo.processInfo.arguments)

    static func fixtureLibrary(in arguments: [String]) -> URL? {
        guard let i = arguments.firstIndex(of: fixtureLibraryArgument), arguments.indices.contains(i + 1) else { return nil }
        return URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
    }

    /// Why a UI-test launch wouldn't be isolated, or nil when it would: it must be the UI-test build (so its settings
    /// aren't the user's). On the Mac (`needsTemporaryHome`), where the user's files share one home, the temporary home
    /// must also be in /tmp, already there, and hold every folder Beat keeps data in. Already there, because a home
    /// made after launch is too late: settings then couldn't see the system's (light mode, the default accent) and
    /// nothing saved stuck. On iOS the UI-test build's own container holds all its files.
    static func isolationProblem(bundleID: String?, home: String?, homeExists: Bool, dataFolders: [URL?],
                                 needsTemporaryHome: Bool = true) -> String? {
        guard let bundleID, bundleID.hasSuffix(uiTestBundleSuffix) else {
            return "\(bundleID ?? "no bundle ID") isn't the UI-test build (the UITest configuration)"
        }
        guard needsTemporaryHome else { return nil }
        guard let home, !home.isEmpty else { return "\(homeVariable) isn't set" }
        let root = URL(fileURLWithPath: home, isDirectory: true).standardizedFileURL.path
        guard root.hasPrefix("/tmp/") || root.hasPrefix("/private/tmp/") else { return "\(root) isn't in /tmp" }
        guard homeExists else { return "\(root) doesn't exist; it must be made before Beat launches (make mac-test-ui does)" }
        for folder in dataFolders {
            guard let path = folder?.standardizedFileURL.path else { return "a data folder couldn't be found" }
            guard path == root || path.hasPrefix(root + "/") else { return "\(path) is outside \(root)" }
        }
        return nil
    }

    /// Called first thing at launch. In a UI-test launch, stops Beat unless it's the UI-test build and, on the Mac, its
    /// folders are all in the temporary home: a test that silently wrote to the real ones could lose the user's pages.
    /// Then, for a fresh start, clears what an earlier launch left.
    static func checkIsolation() {
        guard isUITestLaunch else { return }
        let files = FileManager.default
        guard let fixtureLibrary, files.fileExists(atPath: fixtureLibrary.path) else {
            fatalError("UI-test launch without its fixture folder, stopping before touching any data: \(fixtureLibrary?.path ?? "none given")")
        }
        let home = ProcessInfo.processInfo.environment[homeVariable]
        var isFolder: ObjCBool = false
        let homeExists = home.map { files.fileExists(atPath: $0, isDirectory: &isFolder) && isFolder.boolValue } ?? false
        let folders = [FileManager.SearchPathDirectory.applicationSupportDirectory, .cachesDirectory, .documentDirectory]
            .map { files.urls(for: $0, in: .userDomainMask).first }
        let bundleID = Bundle.main.bundleIdentifier
        #if os(macOS)
        let needsTemporaryHome = true
        #else
        let needsTemporaryHome = false
        #endif
        if let problem = isolationProblem(bundleID: bundleID, home: home, homeExists: homeExists, dataFolders: folders,
                                          needsTemporaryHome: needsTemporaryHome) {
            fatalError("UI-test launch not isolated, stopping before touching any data: \(problem)")
        }
        guard ProcessInfo.processInfo.arguments.contains(freshStartArgument), let bundleID else { return }
        // The folders just checked (the Mac's temporary home, or the UI-test build's own container on iOS), before any
        // store has read anything.
        for folder in folders.compactMap({ $0 }) { try? files.removeItem(at: folder) }
        // Key by key, leaving the domain itself in place for what this launch saves.
        for key in (UserDefaults.standard.persistentDomain(forName: bundleID) ?? [:]).keys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
