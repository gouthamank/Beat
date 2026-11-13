import SwiftUI

struct PlaybackCommands: Commands {
    let queue: PlaybackQueue
    let navigator: AppNavigator

    var body: some Commands {
        CommandMenu("Controls") {
            Button(queue.isPlaying ? "Pause" : "Play", action: queue.togglePlayPause)
                .disabled(queue.current == nil)
            Button("Next", action: queue.next)
                .keyboardShortcut(.rightArrow, modifiers: .command)
                .disabled(queue.current == nil)
            Button("Previous", action: queue.previous)
                .keyboardShortcut(.leftArrow, modifiers: .command)
                .disabled(queue.current == nil)
            Divider()
            Button(navigator.showingNowPlaying ? "Hide Now Playing" : "Show Now Playing") {
                navigator.showingNowPlaying.toggle()
            }
            .keyboardShortcut("l", modifiers: .command)
            .disabled(queue.current == nil)
            Divider()
            Button(queue.isShuffled ? "Turn Shuffle Off" : "Turn Shuffle On", action: queue.toggleShuffle)
            Button("Repeat: \(queue.repeatMode.rawValue.capitalized)", action: queue.cycleRepeat)
            Divider()
            // Beat's volume doesn't reach an AirPlay speaker (see OutputRoute).
            Button("Increase Volume") { queue.volume = min(queue.volume + 0.1, 1) }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(queue.output.isExternal)
            Button("Decrease Volume") { queue.volume = max(queue.volume - 0.1, 0) }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(queue.output.isExternal)
            Button(queue.isMuted ? "Unmute" : "Mute", action: queue.toggleMute)
                .keyboardShortcut(.downArrow, modifiers: [.option, .command])
                .disabled(queue.output.isExternal)
        }
    }
}
