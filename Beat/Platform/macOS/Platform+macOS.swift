import AppKit
import IOKit.pwr_mgt
import SwiftUI

// The Mac's side of the platform layer (see Platform.swift): the same names as Platform/iOS/Platform+iOS.swift, so
// shared code never names AppKit or UIKit.

typealias PlatformImage = NSImage
typealias PlatformColor = NSColor

extension NSImage {
    /// At the bitmap's own pixel size, as `UIImage(cgImage:)` is.
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    var cg: CGImage? { cgImage(forProposedRect: nil, context: nil, hints: nil) }

    /// Reads the file only when drawn.
    static func referencing(_ url: URL) -> NSImage? { NSImage(byReferencing: url) }
}

extension Image {
    init(platformImage: PlatformImage) { self.init(nsImage: platformImage) }
}

/// Opens a web page (Last.fm sign-in, Discogs links) in the default browser.
@MainActor
func openExternally(_ url: URL) {
    NSWorkspace.shared.open(url)
}

extension Notification.Name {
    /// The app came to the front.
    static let appDidBecomeActive = NSApplication.didBecomeActiveNotification
}

/// The system's privacy settings for media access, for the "No Access" screen.
@MainActor
func openPrivacySettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media")!)
}

extension View {
    /// Shows or hides the window's toolbar.
    func windowToolbar(_ visibility: Visibility) -> some View {
        toolbar(visibility, for: .windowToolbar)
    }

    /// The pointing-hand cursor over something clickable.
    func linkPointer(_ on: Bool) -> some View {
        pointerStyle(on ? .link : nil)
    }

    /// A button that reads as a link.
    func linkButtonStyle() -> some View {
        buttonStyle(.link)
    }

    /// A sheet's size: fixed, since a Mac sheet is sized by its content.
    func sheetSize(width: CGFloat, height: CGFloat? = nil) -> some View {
        frame(width: width, height: height)
    }
}

/// The system's Reduce Motion setting, for code outside a view (views read `\.accessibilityReduceMotion`).
@MainActor
func systemReducesMotion() -> Bool {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
}

extension Color {
    /// The window's plain background: behind pages, and under cover backdrops while they fade.
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let keyboardFocus = Color(nsColor: .keyboardFocusIndicatorColor)
}

/// The device, for text about what stays where ("saves the answers on this Mac").
@MainActor
var thisDevice: String { "this Mac" }

/// What to do when the library has no songs Beat can play.
@MainActor
var emptyLibraryHint: String {
    "Beat plays the local, DRM-free songs in your Music library. Add some in Music and they'll appear here."
}

extension SearchFieldPlacement {
    /// A page's search field: in the window toolbar.
    static var page: SearchFieldPlacement { .toolbar }
}

/// The window's bottom safe area, for the now-playing bar: none on the Mac.
@MainActor
func windowBottomInset() -> CGFloat { 0 }

/// The power assertion holding the display awake, while one is held.
@MainActor private var displayAwake: IOPMAssertionID?

/// Keeps the display from sleeping while something is being watched rather than clicked: lyrics or the visualizer.
@MainActor
func keepScreenAwake(_ on: Bool) {
    if on, displayAwake == nil {
        var id: IOPMAssertionID = 0
        let made = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                               IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "Beat is showing lyrics or the visualizer" as CFString, &id)
        if made == kIOReturnSuccess { displayAwake = id }
    } else if !on, let id = displayAwake {
        IOPMAssertionRelease(id)
        displayAwake = nil
    }
}
