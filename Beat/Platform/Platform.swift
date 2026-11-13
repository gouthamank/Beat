import SwiftUI

// The platform layer. Shared code reaches AppKit or UIKit only through names defined twice, once per platform, in
// Platform/macOS/Platform+macOS.swift and Platform/iOS/Platform+iOS.swift (each target compiles one):
// `PlatformImage`, `PlatformColor`, `Image(platformImage:)`, `openExternally`, `openPrivacySettings`,
// `.appDidBecomeActive`, `windowToolbar`, `linkPointer`, `linkButtonStyle`, `sheetSize`, `systemReducesMotion`,
// `Color.windowBackground`/`keyboardFocus`, `emptyLibraryHint`, `thisDevice`, `keepScreenAwake`, `SearchFieldPlacement.page`, `windowBottomInset`.
// What's the same on both lives here.

extension View {
    /// The page's subtitle under its title ("368 albums · 41.2 GB").
    func pageSubtitle(_ text: String) -> some View {
        navigationSubtitle(text)
    }
}

extension EnvironmentValues {
    /// A phone-width layout: an iPhone, or an iPad in a narrow split. Views stack and shrink their Mac layouts when
    /// it's on. Always false on the Mac, so its layouts never change. Set once, in `RootView`.
    @Entry var compactLayout = false
}

extension EnvironmentValues {
    /// The page's side margin for shelves, grids and element headers: narrower on a phone.
    var pageInset: CGFloat { compactLayout ? 16 : 24 }
}
