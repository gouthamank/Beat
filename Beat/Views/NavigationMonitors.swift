import AppKit
import SwiftUI

// AppKit event monitors for navigation SwiftUI doesn't expose: clicking the already-selected sidebar row,
// and the trackpad swipe back. Both look at the event before SwiftUI does and let it through unless
// they've handled it.

/// Clicking the selected sidebar page again goes back to its top level (or scrolls it to the top).
/// SwiftUI's `List` reports no change for a click on the selected row, and tagged sidebar rows can't take
/// gestures without breaking selection, so the click is spotted here instead.
@MainActor
enum SidebarReclickMonitor {
    private static var monitor: Any?

    static func install(navigator: AppNavigator) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak navigator] event in
            MainActor.assumeIsolated {
                guard event.clickCount == 1, !event.modifierFlags.contains(.control), let navigator,
                      let hit = NavigationEvents.hitView(event),
                      let table = NavigationEvents.enclosing(NSTableView.self, of: hit),
                      NavigationEvents.isInSidebar(table) else { return }
                // The monitor runs before the click is handled, so `selectedRow` is still the old selection.
                let row = table.row(at: table.convert(event.locationInWindow, from: nil))
                if row >= 0, row == table.selectedRow { navigator.reselect() }
            }
            return event
        }
    }
}

/// Swiping right with two fingers (or three, depending on the trackpad setting) goes back, like Safari.
/// Back only; the system stack can't follow the fingers, so a chevron at the page's edge does instead
/// (`SwipeBackIndicator`).
@MainActor
enum SwipeBackMonitor {
    private static var monitor: Any?

    static func install(navigator: AppNavigator) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .swipe]) { [weak navigator] event in
            guard let navigator else { return event }
            let handled = MainActor.assumeIsolated { handle(event, navigator) }
            return handled ? nil : event
        }
    }

    private static func handle(_ event: NSEvent, _ navigator: AppNavigator) -> Bool {
        guard navigator.canGoBack, !navigator.showingNowPlaying, navigator.artViewer == nil,
              let window = event.window, window === NSApp.mainWindow, window.attachedSheet == nil else { return false }

        if event.type == .swipe {
            // Three-finger "swipe between pages": positive deltaX is a swipe back.
            guard event.deltaX > 0, let hit = NavigationEvents.hitView(event), !NavigationEvents.isInSidebar(hit)
            else { return false }
            navigator.goBack()
            return true
        }

        // The first event of a gesture often has no movement yet, so decide on the first one that does
        // (began or changed), once per gesture.
        if event.phase == .began { decided = false }
        guard !decided, event.phase == .began || event.phase == .changed, NSEvent.isSwipeTrackingFromScrollEventsEnabled,
              event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return false }
        decided = true
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return false }
        // Fingers moving right, whichever way the user's scroll direction setting runs.
        let fingersRight = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX > 0 : event.scrollingDeltaX < 0
        // Hit-testing the window is the expensive part (SwiftUI checks every view under the pointer), so it
        // comes last, once per gesture rather than on every scroll event.
        // A shelf that can still scroll left gets the gesture, as Safari leaves it to a scrollable page.
        guard fingersRight, let hit = NavigationEvents.hitView(event), !NavigationEvents.isInSidebar(hit),
              !NavigationEvents.canScrollLeft(hit) else { return false }

        let state = SwipeState()
        event.trackSwipeEvent(options: [.lockDirection, .clampGestureAmount],
                              dampenAmountThresholdMin: 0, max: 1) { amount, phase, isComplete, _ in
            MainActor.assumeIsolated {
                guard !state.done else { return }
                navigator.swipeProgress = max(0, amount)
                // Ended means the swipe counts: go back as the fingers lift rather than after the system's
                // settle animation. Cancelled (or completing without ending) means it didn't.
                if phase == .ended || phase == .cancelled || isComplete {
                    state.done = true
                    navigator.swipeProgress = 0
                    if phase == .ended { navigator.goBack() }
                }
            }
        }
        return true
    }

    /// Whether the current scroll gesture has been looked at; reset at each new gesture.
    private static var decided = false

    private final class SwipeState {
        var done = false
    }
}

/// View-hierarchy lookups shared by the monitors.
@MainActor
enum NavigationEvents {
    static func hitView(_ event: NSEvent) -> NSView? {
        guard let content = event.window?.contentView else { return nil }
        // `hitTest` takes a point in the receiver's superview; the content view's superview uses window coordinates.
        if let frame = content.superview { return frame.hitTest(event.locationInWindow) }
        return content.hitTest(content.convert(event.locationInWindow, from: nil))
    }

    static func enclosing<V: NSView>(_ type: V.Type, of view: NSView) -> V? {
        var current: NSView? = view
        while let v = current {
            if let match = v as? V { return match }
            current = v.superview
        }
        return nil
    }

    /// Whether `view` is in the window's sidebar: the leading pane of the split view.
    static func isInSidebar(_ view: NSView) -> Bool {
        var current = view.superview
        while let v = current {
            if let split = v as? NSSplitView, split.isVertical, let leading = split.arrangedSubviews.first,
               split.arrangedSubviews.count > 1 {
                return view.isDescendant(of: leading)
            }
            current = v.superview
        }
        return false
    }

    /// Whether a horizontally scrolling view under the pointer isn't yet at its leading edge.
    static func canScrollLeft(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let v = current {
            if let scroll = v as? NSScrollView, let document = scroll.documentView,
               document.frame.width > scroll.contentView.bounds.width + 1,
               scroll.contentView.bounds.minX > 0.5 {
                return true
            }
            current = v.superview
        }
        return false
    }
}

/// A back chevron that slides in from the page's leading edge as a swipe back progresses.
struct SwipeBackIndicator: View {
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        let progress = navigator.swipeProgress
        Image(systemName: "chevron.left")
            .font(.system(size: 18, weight: .semibold))
            .frame(width: 44, height: 44)
            .beatGlass(in: Circle())
            .scaleEffect(0.7 + 0.3 * progress)
            .offset(x: -44 + 64 * progress)
            .opacity(Double(progress))
            .allowsHitTesting(false)
            .animation(.interactiveSpring, value: progress)
    }
}
