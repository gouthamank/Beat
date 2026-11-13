import SwiftUI
import UIKit

// The iPad and iPhone side of the main window (see Platform/macOS/Window+macOS.swift for the other).

/// None: the screen sets the width, and the Mac's 680 pt pushed every page off a phone's ~400 pt screen.
let pageColumnMinWidth: CGFloat = 0

extension View {
    /// The window around `RootView`: phone-width layouts, Settings as a sheet, and the keyboard put away by a tap
    /// outside a text field. The window keeps the system's Light or Dark; cover pages take the cover's lightness
    /// themselves, because switching the whole window while a pale album slid in turned the page underneath white.
    func platformWindow(queue: PlaybackQueue, navigator: AppNavigator) -> some View {
        modifier(TouchWindow(navigator: navigator))
    }

    /// On a phone, the root page's button for the sidebar drawer.
    func sidebarDrawerButton() -> some View { modifier(SidebarDrawerButton()) }

    /// On a phone, the sidebar as a drawer over the page (`SidebarDrawer`); a column otherwise.
    func sidebarDrawer<Sidebar: View>(@ViewBuilder sidebar: @escaping () -> Sidebar) -> some View {
        modifier(SidebarDrawerOverlay(sidebar: sidebar))
    }
}

/// Nothing to do: touch has no keyboard focus left behind on the page.
@MainActor
func resignWindowFocus() {}

private struct TouchWindow: ViewModifier {
    let navigator: AppNavigator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        @Bindable var navigator = navigator
        content
            .background { KeyboardDismissal() }
            // The Mac's Settings window, as a sheet; it inherits the window's stores from here.
            .sheet(isPresented: $navigator.showingSettings) {
                NavigationStack {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) { Button("Done") { navigator.showingSettings = false } }
                        }
                }
                .presentationSizing(.page)
            }
            // Outermost, so RootView, its overlays and sheets (the editor, Settings) all get it.
            .environment(\.compactLayout, horizontalSizeClass == .compact)
    }
}

private struct SidebarDrawerButton: ViewModifier {
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.compactLayout) private var compact

    func body(content: Content) -> some View {
        content.toolbar {
            if compact {
                ToolbarItem(placement: .topBarLeading) {
                    Button { navigator.sidebarDrawerOpen = true } label: { Label("Sidebar", systemImage: "sidebar.leading") }
                }
            }
        }
    }
}

private struct SidebarDrawerOverlay<Sidebar: View>: ViewModifier {
    @ViewBuilder let sidebar: () -> Sidebar
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.compactLayout) private var compact

    func body(content: Content) -> some View {
        @Bindable var navigator = navigator
        content.overlay {
            if compact {
                SidebarDrawer(isOpen: $navigator.sidebarDrawerOpen, canSwipeOpen: navigator.path.isEmpty) {
                    NavigationStack {
                        sidebar()
                            .navigationTitle("Beat")
                            // From inside the stack: outside it, the stack still drew its opaque background over the glass.
                            .containerBackground(.clear, for: .navigation)
                    }
                }
            }
        }
    }
}

// MARK: Zoom transitions

extension View {
    /// Album and artist pages zoom out of the tile they're opened from and, with a swipe down, back into it: iOS 26's
    /// zoom transition, which follows the finger. Beat's own cover flight (`HeroTransition`) is off here; it couldn't
    /// follow a swipe. Set once around the navigation stack, so tiles and pages share one namespace.
    func zoomTransitions() -> some View { modifier(ZoomNamespace()) }

    /// A tile that a page zooms out of.
    func zoomSource(_ subject: HeroSubject?) -> some View { modifier(ZoomSource(subject: subject)) }

    /// A pushed page: album and artist pages zoom from their tile (or, opened from elsewhere, from the middle).
    func zoomDestination(_ route: Route) -> some View { modifier(ZoomDestination(route: route)) }
}

extension EnvironmentValues {
    @Entry var zoomNamespace: Namespace.ID?
}

private struct ZoomNamespace: ViewModifier {
    @Namespace private var namespace

    func body(content: Content) -> some View {
        content.environment(\.zoomNamespace, namespace)
    }
}

private struct ZoomSource: ViewModifier {
    let subject: HeroSubject?
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let subject, let namespace {
            content.matchedTransitionSource(id: subject, in: namespace)
        } else {
            content
        }
    }
}

private struct ZoomDestination: ViewModifier {
    let route: Route
    @Environment(\.zoomNamespace) private var namespace

    private var subject: HeroSubject? {
        switch route {
        case .album(let id): .album(id)
        case .artist(let id): .artist(id)
        default: nil
        }
    }

    func body(content: Content) -> some View {
        if let subject, let namespace {
            content.navigationTransition(.zoom(sourceID: subject, in: namespace))
        } else {
            content
        }
    }
}

// MARK: Status bar

extension View {
    /// Has iOS re-read the status bar's style when a cover page's light or dark changes after it appeared (its colours
    /// arrived late). The style comes from the navigation bar's colour scheme, which iOS otherwise reads only as the
    /// page appears, so the bar kept white text on a page that had since turned pale.
    func refreshesStatusBar(for scheme: ColorScheme) -> some View {
        background { StatusBarRefresher(scheme: scheme) }
    }
}

private struct StatusBarRefresher: UIViewRepresentable {
    let scheme: ColorScheme

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        // After SwiftUI has passed the new scheme to the navigation bar.
        DispatchQueue.main.async { [weak view] in
            var controller = view?.window?.rootViewController
            while let current = controller {
                current.setNeedsStatusBarAppearanceUpdate()
                controller = current.presentedViewController
            }
            sequence(first: view as UIResponder?, next: { $0?.next }).compactMap { $0 as? UIViewController }
                .forEach { $0.setNeedsStatusBarAppearanceUpdate() }
        }
    }
}
