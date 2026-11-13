import SwiftUI
import UIKit

/// The system's output menu (this device, headphones, AirPlay speakers and TVs). Each bar gets an empty slot; the
/// one shared picker in `OutputRoute` moves into the front bar's slot, as on the Mac.
struct RoutePicker: UIViewRepresentable {
    let route: OutputRoute

    func makeCoordinator() -> OutputRoute { route }

    func makeUIView(context: Context) -> UIView {
        let slot = UIView()
        route.register(slot)
        return slot
    }

    func updateUIView(_ slot: UIView, context: Context) {}

    static func dismantleUIView(_ slot: UIView, coordinator: OutputRoute) {
        coordinator.unregister(slot)
    }
}
