import AppKit
import SwiftUI

// The Mac's side of the main window (see Platform/iOS/Window+iOS.swift for the other).

/// The narrowest the page column gets, on every page (root or pushed): the window's minimum. See the CLAUDE.md
/// gotcha on the detail column.
let pageColumnMinWidth: CGFloat = 680

extension View {
    /// The window around `RootView`: its minimum height and the AppKit event monitors for what SwiftUI doesn't expose
    /// on the Mac. (Its Light or Dark is `windowAppearance()`, applied inside `RootView`.)
    func platformWindow(queue: PlaybackQueue, navigator: AppNavigator) -> some View {
        modifier(MacWindow(queue: queue, navigator: navigator))
    }

    /// The sidebar is always a column on the Mac.
    func sidebarDrawerButton() -> some View { self }

    /// No status bar on the Mac.
    func refreshesStatusBar(for scheme: ColorScheme) -> some View { self }

    /// The window's Light or Dark, following the cover on album and artist pages. `RootView` applies it to its split
    /// view, where it was before the platform split.
    func windowAppearance() -> some View { modifier(WindowAppearance()) }

    /// The Mac flies covers itself (`HeroTransition`); these are for iPad and iPhone's zoom transition.
    func zoomTransitions() -> some View { self }
    func zoomSource(_ subject: HeroSubject?) -> some View { self }
    func zoomDestination(_ route: Route) -> some View { self }

    /// The sidebar is always a column on the Mac.
    func sidebarDrawer<Sidebar: View>(@ViewBuilder sidebar: @escaping () -> Sidebar) -> some View { self }

    /// Dims the title bar and toolbar while `shown`, matching a SwiftUI dim over the page (Quick Open's). AppKit draws
    /// them above the window's SwiftUI content, so no overlay reaches them; a click there calls `onTap`.
    func titleBarDim(_ shown: Bool, opacity: Double, onTap: @escaping () -> Void) -> some View {
        modifier(TitleBarDim(shown: shown, opacity: opacity, onTap: onTap))
    }
}

private struct TitleBarDim: ViewModifier {
    let shown: Bool
    let opacity: Double
    let onTap: () -> Void
    @State private var dim = TitleBarDimView()

    func body(content: Content) -> some View {
        content.onChange(of: shown) { _, shown in
            dim.onTap = onTap
            if shown { dim.show(in: NSApp.keyWindow ?? NSApp.mainWindow, opacity: opacity) } else { dim.hide() }
        }
    }
}

/// Black over the title bar strip, added to the window's frame view above the toolbar (and the window buttons, as a
/// sheet covers them). Left in place once added, invisible and letting clicks through while hidden.
private final class TitleBarDimView: NSView {
    var onTap: () -> Void = {}

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        alphaValue = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(in window: NSWindow?, opacity: Double) {
        guard let window, let frameView = window.contentView?.superview else { return }
        // Window coordinates: everything above the content layout rect is the title bar and toolbar.
        let content = window.contentLayoutRect
        let bar = NSRect(x: 0, y: content.maxY, width: window.frame.width, height: window.frame.height - content.maxY)
        guard bar.height > 0 else { return }
        frame = frameView.convert(bar, from: nil)
        autoresizingMask = frameView.isFlipped ? [.width, .maxYMargin] : [.width, .minYMargin]
        if superview !== frameView {
            removeFromSuperview()
            frameView.addSubview(self, positioned: .above, relativeTo: nil)
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = opacity
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().alphaValue = 0
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { alphaValue > 0 ? super.hitTest(point) : nil }
    override func mouseDown(with event: NSEvent) { onTap() }
    // A click closes Quick Open rather than dragging the window.
    override var mouseDownCanMoveWindow: Bool { false }
}

/// Lets go of keyboard focus when a full-window view (Now Playing, the cover viewer) comes or goes: a control left
/// focused underneath would take Space and the first Tab. Esc and other shortcuts don't need a focused view.
@MainActor
func resignWindowFocus() {
    Task {
        await Task.yield()
        NSApp.keyWindow?.makeFirstResponder(nil)
    }
}

/// Not `private`: the window's saved frame is stored under a key made from the content's full type name, and a private
/// type's name includes a memory address that changes with every build, so the window never got its size back.
struct MacWindow: ViewModifier {
    let queue: PlaybackQueue
    let navigator: AppNavigator

    func body(content: Content) -> some View {
        content
            // Minimum width is set on RootView's page column (see there).
            .frame(minHeight: 560)
            // iPad and iPhone have the system's own edge swipe and no responder-chain Space.
            .onAppear {
                SpaceBarMonitor.install(queue: queue)
                SidebarReclickMonitor.install(navigator: navigator)
                SearchFocusMonitor.install()
                SwipeBackMonitor.install(navigator: navigator)
            }
    }
}

/// The window's Light or Dark: the cover's on album and artist pages, otherwise the system's (`windowAppearance()`).
private struct WindowAppearance: ViewModifier {
    @Environment(AppNavigator.self) private var navigator
    /// The system's Light or Dark (System Settings ▸ Appearance), kept current while Beat runs.
    @State private var systemScheme = WindowAppearance.currentSystemScheme()

    private static let systemAppearanceChanged = Notification.Name("AppleInterfaceThemeChangedNotification")

    /// Read from the global preference rather than the window, which may be showing a cover's scheme.
    private static func currentSystemScheme() -> ColorScheme {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
    }

    private var windowScheme: ColorScheme {
        navigator.coverTint.current.map { $0.palette.isDark ? .dark : .light } ?? systemScheme
    }

    func body(content: Content) -> some View {
        content
            // While an album or artist page shows its colours, the whole window (toolbar, divider, sidebar
            // material) takes the cover's lightness. Otherwise the system's own Light or Dark, set explicitly:
            // `preferredColorScheme(nil)` doesn't restore a window that was given a scheme, so after a pale cover
            // the sidebar stayed in Light mode.
            .preferredColorScheme(windowScheme)
            .onChange(of: windowScheme) {
                Task {
                    // After the toolbar has rebuilt for the page now in front.
                    try? await Task.sleep(for: .milliseconds(50))
                    Self.resetToolbarSearchFields()
                }
            }
            .onReceive(DistributedNotificationCenter.default().publisher(for: Self.systemAppearanceChanged)) { _ in
                systemScheme = Self.currentSystemScheme()
            }
    }

    /// Back from a cover page, a grid's toolbar search field redrew its bezel in the window's Light or Dark
    /// but kept its text in the page's: black text on a dark field. Setting the text again redraws it in
    /// the window's current colours.
    private static func resetToolbarSearchFields() {
        func reset(_ view: NSView) {
            if let field = view as? NSSearchField {
                field.appearance = nil
                field.textColor = .controlTextColor
                field.stringValue = field.stringValue
                (field.currentEditor() as? NSTextView)?.textColor = .controlTextColor
                field.needsDisplay = true
            }
            view.subviews.forEach(reset)
        }
        for window in NSApp.windows {
            if let frame = window.contentView?.superview { reset(frame) }
        }
    }
}
