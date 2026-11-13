import SwiftUI
import UIKit

// The iPad and iPhone side of the platform layer (see Platform.swift): the same names as
// Platform/macOS/Platform+macOS.swift, so shared code never names AppKit or UIKit.

typealias PlatformImage = UIImage
typealias PlatformColor = UIColor

extension UIImage {
    var cg: CGImage? { cgImage }

    static func referencing(_ url: URL) -> UIImage? { UIImage(contentsOfFile: url.path) }
}

extension Image {
    init(platformImage: PlatformImage) { self.init(uiImage: platformImage) }
}

/// Opens a web page (Last.fm sign-in, Discogs links) in the default browser.
@MainActor
func openExternally(_ url: URL) {
    UIApplication.shared.open(url)
}

extension Notification.Name {
    /// The app came to the front.
    static let appDidBecomeActive = UIApplication.didBecomeActiveNotification
}

/// Beat's own page in Settings, where Media & Apple Music access is switched on, for the "No Access" screen.
@MainActor
func openPrivacySettings() {
    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
}

extension View {
    /// Shows or hides the navigation bar, the counterpart of the Mac's window toolbar.
    func windowToolbar(_ visibility: Visibility) -> some View {
        toolbar(visibility, for: .navigationBar)
    }

    /// No pointer to change on a touch screen.
    func linkPointer(_ on: Bool) -> some View { self }

    /// A button that reads as a link: borderless and tinted.
    func linkButtonStyle() -> some View {
        buttonStyle(.borderless)
    }

    /// The system sizes sheets to the screen; a fixed Mac width overflowed a phone.
    func sheetSize(width: CGFloat, height: CGFloat? = nil) -> some View { self }
}

/// The system's Reduce Motion setting, for code outside a view (views read `\.accessibilityReduceMotion`).
@MainActor
func systemReducesMotion() -> Bool {
    UIAccessibility.isReduceMotionEnabled
}

extension Color {
    /// The window's plain background: behind pages, and under cover backdrops while they fade.
    static let windowBackground = Color(uiColor: .systemBackground)
    static let keyboardFocus = Color.accentColor
}

/// The device, for text about what stays where ("saves the answers on this iPhone").
@MainActor
var thisDevice: String { UIDevice.current.userInterfaceIdiom == .pad ? "this iPad" : "this iPhone" }

/// What to do when the library has no songs Beat can play, for this device's library source.
@MainActor
var emptyLibraryHint: String {
    let device = UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    #if targetEnvironment(simulator)
    return "The Simulator has no music library. Drag audio files onto it, save them to Files › On My \(device) › Beat › Music, then relaunch Beat."
    #else
    return "Beat plays the music synced to this \(device) from your Mac. Connect it, select it in Finder, and sync music under Music. Turn off Sync Library on the \(device) first: songs from iCloud can't be played by other apps."
    #endif
}

extension SearchFieldPlacement {
    /// A page's search field: under the title, since a toolbar field sits at the bottom of the screen, under the
    /// now-playing bar. Always shown: tucked away (`.automatic`), it started half revealed at launch, an empty pill
    /// under the title (cause not found yet; see TODO.md).
    static var page: SearchFieldPlacement { .navigationBarDrawer(displayMode: .always) }
}

/// The key window's safe areas. A view's own safe area also counts bars the page puts at the bottom, which floated
/// the now-playing bar high above the screen's edge.
@MainActor
private var keyWindowInsets: UIEdgeInsets {
    UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets ?? .zero
}

/// The window's bottom safe area (the home indicator), for the now-playing bar.
@MainActor
func windowBottomInset() -> CGFloat { keyWindowInsets.bottom }

/// Keeps the screen on (auto-lock off) while something is being watched rather than tapped: lyrics or the visualizer.
/// iOS applies it only while Beat is in front.
@MainActor
func keepScreenAwake(_ on: Bool) {
    UIApplication.shared.isIdleTimerDisabled = on
}
