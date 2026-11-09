import AVKit
import Combine
import Observation

/// Beat's one output (AirPlay) picker. Every `AVRoutePickerView` given a player attaches a fresh output
/// context to it, which drops the current AirPlay route; with a picker in each page's now-playing bar,
/// opening or leaving a page disconnected AirPlay. So there's a single picker, given the player once,
/// lent to whichever bar is in front (the one shown most recently).
@MainActor
@Observable
final class OutputRoute {
    /// Playing to AirPlay. Beat's own volume doesn't reach the speaker then, and macOS offers apps no
    /// public way to set the speaker's volume, so the slider steps aside.
    private(set) var isExternal = false
    /// The picker's button has keyboard focus. AppKit's own focus ring would draw outside the picker's small
    /// slot and is clipped, so the bar draws one from this.
    private(set) var hasFocus = false

    @ObservationIgnored let picker = SingleStopRoutePicker()
    @ObservationIgnored private var hosts: [Host] = []
    @ObservationIgnored private var externalWatch: AnyCancellable?

    private struct Host {
        weak var view: NSView?
    }

    init(player: AVPlayer) {
        picker.isRoutePickerButtonBordered = false
        picker.setRoutePickerButtonColor(.secondaryLabelColor, for: .normal)
        picker.setRoutePickerButtonColor(.labelColor, for: .normalHighlighted)
        picker.setRoutePickerButtonColor(.controlAccentColor, for: .active)
        picker.setRoutePickerButtonColor(.controlAccentColor, for: .activeHighlighted)
        picker.player = player
        // Delivered on the main queue, so the main-actor closure is safe.
        externalWatch = player.publisher(for: \.isExternalPlaybackActive)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] active in self?.isExternal = active }
    }

    /// A bar appeared: it becomes the front host and shows the picker.
    func register(_ host: NSView) {
        hosts.removeAll { $0.view == nil || $0.view === host }
        hosts.append(Host(view: host))
        attach(to: host)
    }

    /// A bar went away: the picker goes back to the bar that was in front before it.
    func unregister(_ host: NSView) {
        hosts.removeAll { $0.view == nil || $0.view === host }
        guard picker.superview === host || picker.superview == nil, let previous = hosts.last?.view else { return }
        attach(to: previous)
    }

    /// The window's first responder changed (see `RoutePicker`).
    func firstResponderChanged(in window: NSWindow) {
        let focused = (window.firstResponder as? NSView)?.isDescendant(of: picker) == true
        if focused != hasFocus { hasFocus = focused }
    }

    private func attach(to host: NSView) {
        guard picker.superview !== host else { return }
        picker.removeFromSuperview()
        picker.frame = host.bounds
        picker.autoresizingMask = [.width, .height]
        host.addSubview(picker)
    }
}

/// `AVRoutePickerView` and the button inside it both take keyboard focus, so Tab stopped on the picker twice;
/// only the button keeps it. The button ignores Space, which then fell through to play/pause, so the picker
/// (next in the responder chain) presses it.
final class SingleStopRoutePicker: AVRoutePickerView {
    override var acceptsFirstResponder: Bool { false }
    override var canBecomeKeyView: Bool { false }

    override func keyDown(with event: NSEvent) {
        let isPlainSpace = event.keyCode == 49
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isDisjoint(with: [.command, .option, .control, .shift])
        if isPlainSpace, let button = subviews.first(where: { $0 is NSButton }) as? NSButton {
            button.performClick(nil)
        } else {
            super.keyDown(with: event)
        }
    }
}
