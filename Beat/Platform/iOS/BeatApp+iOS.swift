import AVFoundation
import SwiftUI

// The iPad and iPhone side of the app (see Platform/macOS/BeatApp+macOS.swift for the other).

/// A music player's audio session: plays on with the screen locked or the silent switch on (with the background
/// audio mode in Info.plist), and other apps' audio pauses for it.
@MainActor
func configurePlatform() {
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, policy: .longFormAudio)
}

extension Scene {
    func platformWindowStyle() -> some Scene { self }
}

/// Nothing beyond the shared menus (shown for a hardware keyboard): Settings is a sheet and there's no About panel.
struct PlatformCommands: Commands {
    var body: some Commands { EmptyCommands() }
}
