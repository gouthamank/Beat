import Foundation

/// The version people see, the same on every platform: "1.2.0" (`CFBundleShortVersionString`, raised by hand for a
/// release in project.yml) and the commit `make` stamps in ("26fab3d", "-dirty" with uncommitted changes; "dev" from
/// Xcode). The build number stays in Info.plist, unshown.
enum AppVersion {
    static var version: String { info("CFBundleShortVersionString") }
    static var commit: String { info("BeatCommit") }

    /// "1.2.0 (26fab3d)", or just the version without a commit.
    static var display: String { commit.isEmpty ? version : "\(version) (\(commit))" }

    private static func info(_ key: String) -> String { Bundle.main.infoDictionary?[key] as? String ?? "" }
}
