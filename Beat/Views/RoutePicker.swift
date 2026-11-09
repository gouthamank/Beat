import AVKit
import SwiftUI

/// The system's own output menu (this Mac, headphones, AirPlay speakers and TVs), as in Control Center.
/// Bound to Beat's player, so it routes Beat only and leaves the system output and other apps alone.
/// Each bar gets an empty slot; the one shared picker in `OutputRoute` moves into the front bar's slot,
/// because creating a picker per bar reset the route (see `OutputRoute`).
struct RoutePicker: NSViewRepresentable {
    let route: OutputRoute

    func makeCoordinator() -> OutputRoute { route }

    func makeNSView(context: Context) -> NSView {
        let slot = PickerSlot()
        slot.route = route
        route.register(slot)
        return slot
    }

    func updateNSView(_ slot: NSView, context: Context) {}

    static func dismantleNSView(_ slot: NSView, coordinator: OutputRoute) {
        coordinator.unregister(slot)
    }
}

/// Tells the route when its window's first responder changes, so the bar can show the picker's focus.
private final class PickerSlot: NSView {
    weak var route: OutputRoute?
    private var watch: NSKeyValueObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        watch = window?.observe(\.firstResponder, options: [.initial, .new]) { [weak self] window, _ in
            // First responder changes happen on the main thread.
            MainActor.assumeIsolated { self?.route?.firstResponderChanged(in: window) }
        }
    }
}
