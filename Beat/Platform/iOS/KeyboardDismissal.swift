import SwiftUI
import UIKit

/// Ends text editing when a tap lands outside a text field, as people expect on iPad and iPhone; SwiftUI keeps the
/// keyboard up otherwise. One recognizer on the window that never claims the tap, so buttons, rows and the field
/// being tapped work as before. Sheets present in the same window, so it covers them too.
struct KeyboardDismissal: UIViewRepresentable {
    func makeUIView(context: Context) -> KeyboardDismissalView { KeyboardDismissalView() }
    func updateUIView(_ view: KeyboardDismissalView, context: Context) {}
}

final class KeyboardDismissalView: UIView, UIGestureRecognizerDelegate {
    private var recognizer: UITapGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window, recognizer?.view !== window else { return }
        if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapOutside(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        recognizer = tap
    }

    @objc private func tapOutside(_ tap: UITapGestureRecognizer) {
        tap.view?.endEditing(true)
    }

    /// Taps on a text field or text view (moving the caret, picking another field) leave the keyboard alone.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let current = view {
            if current is UITextField || current is UITextView || current is UISearchBar { return false }
            view = current.superview
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
