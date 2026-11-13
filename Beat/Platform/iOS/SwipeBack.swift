import SwiftUI
import UIKit

/// Brings back the swipe from the left edge (and iOS 26's swipe anywhere) on pages that hide the system back button.
/// Hiding it (`coverPageChrome`) turns the system's back swipe off as well, so album and artist pages couldn't be
/// swiped away. The pop goes through the stack as usual, so `AppNavigator.path` hears about it.
struct SwipeBackEnabler: UIViewRepresentable {
    func makeUIView(context: Context) -> SwipeBackProbe { SwipeBackProbe() }
    func updateUIView(_ view: SwipeBackProbe, context: Context) {}
}

final class SwipeBackProbe: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        // After the hosting controller has joined its navigation controller.
        DispatchQueue.main.async { [weak self] in
            guard let navigation = self?.navigationController else { return }
            for recognizer in [navigation.interactivePopGestureRecognizer, navigation.interactiveContentPopGestureRecognizer] {
                recognizer?.isEnabled = true
                recognizer?.delegate = PopGestureDelegate.shared
            }
        }
    }

    private var navigationController: UINavigationController? {
        sequence(first: self as UIResponder, next: \.next).lazy.compactMap { $0 as? UINavigationController }.first
    }
}

/// Lets the swipe start whenever there's a page to go back to (the system's own delegate refuses while back is hidden).
private final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    static let shared = PopGestureDelegate()

    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let view = recognizer.view else { return false }
        let navigation = sequence(first: view as UIResponder, next: \.next).lazy.compactMap { $0 as? UINavigationController }.first
        return (navigation?.viewControllers.count ?? 0) > 1
    }
}
