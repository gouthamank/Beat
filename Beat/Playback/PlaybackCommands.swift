import AppKit
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

/// Space plays and pauses when nothing else wants it. It isn't a menu shortcut or an event monitor, which
/// would take Space before anything else: spaces typed into search fields, and Space pressing the button
/// that has keyboard focus (as everywhere on a Mac), must win. So Space travels the normal way, focused
/// control first, and play/pause sits at the end of each window's responder chain, catching only what
/// nothing handled. (SwiftUI hides which view has focus, so checking for focus up front isn't possible.)
///
/// One exception: lists. An AppKit list with focus (the sidebar, once clicked) uses typed characters to jump to
/// rows and swallowed Space, so play/pause stopped working until something cleared the focus. Beat's lists
/// have no use for Space, so while one has focus a monitor takes Space first.
@MainActor
enum SpaceBarMonitor {
    private static var observer: NSObjectProtocol?
    private static var listMonitor: Any?
    private static let catcher = SpaceCatcher()

    static func install(queue: PlaybackQueue) {
        guard observer == nil else { return }
        catcher.queue = queue
        listMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let handled = MainActor.assumeIsolated {
                guard SpaceCatcher.isPlainSpace(event), event.window?.firstResponder is NSTableView,
                      let queue = catcher.queue else { return false }
                queue.togglePlayPause()
                return true
            }
            return handled ? nil : event
        }
        NSApp.windows.forEach(attach)
        // Windows open later (Settings), and SwiftUI may rebuild a window's chain.
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { attach(window) }
        }
    }

    private static func attach(_ window: NSWindow) {
        var last: NSResponder = window
        while let next = last.nextResponder {
            if next === catcher { return }
            last = next
        }
        last.nextResponder = catcher
    }
}

private final class SpaceCatcher: NSResponder {
    weak var queue: PlaybackQueue?

    override func keyDown(with event: NSEvent) {
        if Self.isPlainSpace(event), let queue { queue.togglePlayPause() } else { super.keyDown(with: event) }
    }

    static func isPlainSpace(_ event: NSEvent) -> Bool {
        event.keyCode == 49
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isDisjoint(with: [.command, .option, .control, .shift])
    }
}
