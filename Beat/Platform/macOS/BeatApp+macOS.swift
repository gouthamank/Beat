import AppKit
import SwiftUI

// The Mac's side of the app (see Platform/iOS/BeatApp+iOS.swift for the other).

/// One window, no tabs: View ▸ Show Tab Bar let a second tab open a second copy of the whole UI, which broke it (the
/// now-playing bar, Now Playing and transitions all assume one window). This removes the tab items.
@MainActor
func configurePlatform() {
    NSWindow.allowsAutomaticWindowTabbing = false
}

extension Scene {
    func platformWindowStyle() -> some Scene { windowToolbarStyle(.unified) }
}

/// About Beat with the build's commit, and the sidebar's View menu items.
struct PlatformCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Beat") { AboutPanel.show() }
        }
        SidebarCommands()
    }
}

extension BeatApp {
    /// Beat ▸ Settings… (⌘,). Everything the main window has: Settings hosts the element editor (for new-element
    /// defaults), whose preview renders real elements.
    var settingsWindow: some Scene {
        Settings { withStores(SettingsView()) }
    }
}

/// The standard About panel, with the build's commit beside its build number: "Version 1.0 (42 · a1b2c3d)".
@MainActor
enum AboutPanel {
    static func show() {
        let info = Bundle.main.infoDictionary ?? [:]
        let build = info["CFBundleVersion"] as? String ?? ""
        let commit = info["BeatCommit"] as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [.applicationVersion: commit.isEmpty ? build : "\(build) · \(commit)"])
        NSApp.activate()
    }
}
