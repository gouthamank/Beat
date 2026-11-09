import AppKit
import SwiftUI

// Cross-hierarchy transitions (album zoom, Now Playing morph) measure views in window coordinates
// through tiny AppKit probes. `matchedGeometryEffect` and SwiftUI's `.global` space don't reach across
// macOS's separately hosted split-view columns and pushed pages, but window coordinates do.

/// A handle to a probed view's frame, in window coordinates with a top-left origin.
@MainActor
final class FrameProbe {
    fileprivate weak var view: FrameProbeView?

    var windowRect: CGRect? {
        guard let rect = view?.windowRect(), rect.width > 0, rect.height > 0 else { return nil }
        return rect
    }

    /// The size of the window's content area, for drawing something as if it covered the whole window.
    var windowSize: CGSize? { view?.window?.contentView?.bounds.size }

}

final class FrameProbeView: NSView {
    /// Never takes clicks; it only measures.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func windowRect() -> CGRect? {
        guard let window, let content = window.contentView else { return nil }
        let r = convert(bounds, to: nil)
        return CGRect(x: r.minX, y: content.bounds.height - r.maxY, width: r.width, height: r.height)
    }
}

private struct FrameProbeReader: NSViewRepresentable {
    let probe: FrameProbe

    func makeNSView(context: Context) -> FrameProbeView {
        let view = FrameProbeView()
        probe.view = view
        return view
    }

    func updateNSView(_ view: FrameProbeView, context: Context) {
        probe.view = view
    }
}

extension View {
    /// Lets `probe` report this view's window frame on demand.
    func frameProbe(_ probe: FrameProbe) -> some View {
        background(FrameProbeReader(probe: probe))
    }
}

extension EnvironmentValues {
    /// Set by the editor's preview, where opening an album would navigate the real window behind the sheet.
    @Entry var albumNavigationDisabled = false
    /// Set by the element editor's preview: items show exactly as on the page but take no clicks or hover
    /// (their scroll views still scroll).
    @Entry var elementPreview = false
}

/// Navigation motion, in one place so it stays consistent and quick: covers flying, colours fading,
/// full-window views morphing.
enum Motion {
    static let flightDuration = 0.28
    static let flight = Animation.spring(duration: flightDuration, bounce: 0.1)
    static let fadeDuration = 0.18
    static let fade = Animation.easeOut(duration: fadeDuration)
    static let morphOpen = Animation.spring(duration: 0.32, bounce: 0.08)
    static let morphClose = Animation.spring(duration: 0.26, bounce: 0)
}

// MARK: Album zoom

/// What a zoom flies: an album's cover, or an artist's art (photo or cover mosaic).
enum HeroSubject: Hashable, Sendable {
    case album(PersistentID)
    case artist(String)
}

/// The art flying between a tile and its page's header (album or artist): out of the tile when the page
/// opens, and back into a tile when it's popped. Album-only calls below are shorthands for `.album(id)`.
@MainActor
@Observable
final class HeroTransition {
    struct Flight: Equatable {
        enum Direction { case open, close }

        let id = UUID()
        let subject: HeroSubject
        /// Window coordinates, top-left origin.
        let from: CGRect
        var direction = Direction.open
    }

    private struct Tile {
        let probe: FrameProbe
        let cornerRadius: CGFloat
    }

    /// A page's colours fading out over the page underneath, after the page has gone.
    struct BackdropFade: Equatable {
        let id = UUID()
        /// The album whose colours the page showed (an artist page's is its featured album).
        let albumID: PersistentID
        /// Window coordinates, top-left origin.
        let rect: CGRect
    }

    private(set) var flight: Flight?
    private(set) var backdropFade: BackdropFade?
    /// The tile last opened from keeps its probe, so the art can fly back to it. Other tiles only carry one
    /// while the pointer is on them: ~150 AppKit probes on a big artist's page made scrolling choppy.
    private(set) var lastOpened: HeroSubject?
    /// The page's header art, registered when the page appears.
    @ObservationIgnored private(set) var target: (subject: HeroSubject, probe: FrameProbe)?
    /// The page as a whole and the album its colours come from, for where and how they fade out.
    @ObservationIgnored private var page: (subject: HeroSubject, probe: FrameProbe, albumID: PersistentID?)?
    /// The tile each page was opened from, preferred when flying back.
    @ObservationIgnored private var sources: [HeroSubject: Tile] = [:]
    /// The most recently shown tile per subject, for flying back after a Library jump rebuilt the page
    /// underneath. Probes hold their views weakly, so a gone tile just measures as nil.
    @ObservationIgnored private var tiles: [HeroSubject: Tile] = [:]

    static let headerCornerRadius: CGFloat = 12

    func depart(_ subject: HeroSubject, from rect: CGRect) {
        flight = Flight(subject: subject, from: rect)
    }

    func setTarget(_ probe: FrameProbe, for subject: HeroSubject) {
        target = (subject, probe)
    }

    func setTarget(_ probe: FrameProbe, for albumID: PersistentID) { setTarget(probe, for: .album(albumID)) }

    /// `colours` is the album the page's background comes from, for its fade-out.
    func setPage(_ probe: FrameProbe, for subject: HeroSubject, colours albumID: PersistentID?) {
        page = (subject, probe, albumID)
    }

    func setPage(_ probe: FrameProbe, for albumID: PersistentID) { setPage(probe, for: .album(albumID), colours: albumID) }

    /// The page is leaving the front (popped, covered, or its sidebar page switched away): keep its colours
    /// on screen a moment longer and fade them. Called while the page still measures.
    func fadeBackdrop(_ subject: HeroSubject) {
        guard let page, page.subject == subject, let albumID = page.albumID, let rect = page.probe.windowRect else { return }
        backdropFade = BackdropFade(albumID: albumID, rect: rect)
    }

    func clearBackdropFade(_ id: UUID) {
        if backdropFade?.id == id { backdropFade = nil }
    }

    func targetRect(for subject: HeroSubject) -> CGRect? {
        guard let target, target.subject == subject else { return nil }
        return target.probe.windowRect
    }

    func targetRect(for albumID: PersistentID) -> CGRect? { targetRect(for: .album(albumID)) }

    /// Tiles call this when they appear (and when their subject changes), so art can fly back to them.
    func registerTile(_ probe: FrameProbe, for subject: HeroSubject, cornerRadius: CGFloat) {
        tiles[subject] = Tile(probe: probe, cornerRadius: cornerRadius)
    }

    func registerTile(_ probe: FrameProbe, for albumID: PersistentID, cornerRadius: CGFloat) {
        registerTile(probe, for: .album(albumID), cornerRadius: cornerRadius)
    }

    /// The header's spot hides while its art is in the air, either way.
    func isFlying(to subject: HeroSubject) -> Bool { flight?.subject == subject }
    func isFlying(to albumID: PersistentID) -> Bool { isFlying(to: .album(albumID)) }

    /// A tile hides while the art flies back into it, so there's never two.
    func isReturning(to subject: HeroSubject) -> Bool {
        flight?.subject == subject && flight?.direction == .close
    }

    func isReturning(to albumID: PersistentID) -> Bool { isReturning(to: .album(albumID)) }

    func land() { flight = nil }

    /// Opens an album or artist page, zooming its art out of `probe`'s view unless Reduce Motion is on.
    func open(_ subject: HeroSubject, from probe: FrameProbe, cornerRadius: CGFloat = 10,
              navigator: AppNavigator, reduceMotion: Bool) {
        sources[subject] = Tile(probe: probe, cornerRadius: cornerRadius)
        lastOpened = subject
        if !reduceMotion, let rect = probe.windowRect { depart(subject, from: rect) }
        switch subject {
        case .album(let id): navigator.openAlbum(id)
        case .artist(let id): navigator.openArtist(id)
        }
    }

    func open(_ albumID: PersistentID, from probe: FrameProbe, cornerRadius: CGFloat = 10,
              navigator: AppNavigator, reduceMotion: Bool) {
        open(.album(albumID), from: probe, cornerRadius: cornerRadius, navigator: navigator, reduceMotion: reduceMotion)
    }

    /// The page is being popped: fly its header art back to a tile. Called before the page is removed, so
    /// the header still measures.
    func returnFlight(_ subject: HeroSubject) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let rect = targetRect(for: subject) else { return }
        flight = Flight(subject: subject, from: rect, direction: .close)
    }

    /// Where a flight ends: the header when opening; the source tile, else any shown tile, when closing.
    fileprivate func destination(of flight: Flight) -> (rect: CGRect, cornerRadius: CGFloat)? {
        switch flight.direction {
        case .open:
            return targetRect(for: flight.subject).map { ($0, Self.headerCornerRadius) }
        case .close:
            for tile in [sources[flight.subject], tiles[flight.subject]].compactMap({ $0 }) {
                if let rect = tile.probe.windowRect { return (rect, tile.cornerRadius) }
            }
            return nil
        }
    }
}

/// Draws the flying cover above everything. Lives on the split view, outside the navigation stack,
/// because pushed pages cover anything attached to the stack.
struct HeroOverlay: View {
    @Environment(HeroTransition.self) private var hero
    @Environment(ArtworkCache.self) private var artwork
    @Environment(LibraryStore.self) private var library
    @State private var origin = FrameProbe()
    @State private var rect: CGRect?
    @State private var opacity = 1.0
    @State private var cornerRadius = HeroTransition.headerCornerRadius

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            // Under the flying cover, which lands on the page the colours are fading to.
            if let fade = hero.backdropFade {
                BackdropFadeView(fade: fade, origin: origin)
            }
            if let flight = hero.flight, let rect {
                art(flight.subject)
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
                    .offset(x: rect.minX, y: rect.minY)
                    .opacity(opacity)
            }
        }
        .frameProbe(origin)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task(id: hero.flight?.id) { await fly() }
    }

    @ViewBuilder
    private func art(_ subject: HeroSubject) -> some View {
        switch subject {
        case .album(let id):
            cover(id)
        case .artist(let id):
            ArtistArtwork(albumIDs: library.snapshot.artistsByID[id]?.albumIDsNewestFirst ?? [], artistID: id, cornerRadius: 0)
        }
    }

    /// The cached thumbnail straight away, so the cover never flashes a placeholder.
    @ViewBuilder
    private func cover(_ albumID: PersistentID) -> some View {
        if let image = artwork.cachedImage(album: albumID, size: .large) ?? artwork.cachedImage(album: albumID, size: .thumbnail) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            ArtworkView(albumID: albumID, size: .large, cornerRadius: 0)
        }
    }

    private func fly() async {
        guard let flight = hero.flight else { rect = nil; return }
        let base = origin.windowRect?.origin ?? .zero
        func local(_ r: CGRect) -> CGRect { r.offsetBy(dx: -base.x, dy: -base.y) }
        opacity = 1
        cornerRadius = flight.direction == .open ? 10 : HeroTransition.headerCornerRadius
        rect = local(flight.from)

        // Wait for the destination to appear and lay out: the album page's header when opening, the
        // page underneath (with its scroll restored) when closing. Normally a frame or two.
        var destination: (rect: CGRect, cornerRadius: CGFloat)?
        // Checked every frame, so the flight starts the moment the destination exists (gives up after ~0.6 s).
        for _ in 0..<36 {
            try? await Task.sleep(for: .milliseconds(16))
            guard hero.flight?.id == flight.id else { return }
            if let found = hero.destination(of: flight) { destination = found; break }
        }
        guard let destination else {
            // The tile isn't on screen (scrolled away, or on another page): fade where the cover is.
            withAnimation(Motion.fade) { opacity = 0 }
            try? await Task.sleep(for: .seconds(Motion.fadeDuration))
            if hero.flight?.id == flight.id { hero.land() }
            return
        }

        withAnimation(Motion.flight) {
            rect = local(destination.rect)
            cornerRadius = destination.cornerRadius
        }
        try? await Task.sleep(for: .seconds(Motion.flightDuration + 0.02))
        // Hand over: the header art (or tile) reappears as the overlay goes, at the same spot.
        if hero.flight?.id == flight.id { hero.land() }
    }
}

/// A departing album page's background, drawn where the page was and faded out over what's underneath.
private struct BackdropFadeView: View {
    let fade: HeroTransition.BackdropFade
    let origin: FrameProbe
    @Environment(HeroTransition.self) private var hero
    @Environment(ArtworkCache.self) private var artwork
    @AppStorage("appearance.coverColours") private var coverColours = true
    @State private var opacity = 1.0

    var body: some View {
        let base = origin.windowRect?.origin ?? .zero
        let window = origin.windowSize ?? fade.rect.size
        // Window-sized like the page's own background (see WindowAlignedAlbumBackground), shown only where
        // the page was, so the fading copy lines up with what it replaces.
        AlbumBackground(albumID: fade.albumID, palette: coverColours ? artwork.cachedPalette(album: fade.albumID) : nil)
            .frame(width: window.width, height: window.height)
            .offset(x: -base.x, y: -base.y)
            .mask(alignment: .topLeading) {
                Rectangle()
                    .frame(width: fade.rect.width, height: fade.rect.height)
                    .offset(x: fade.rect.minX - base.x, y: fade.rect.minY - base.y)
            }
            .opacity(opacity)
            .task(id: fade.id) {
                opacity = 1
                withAnimation(Motion.fade) { opacity = 0 }
                try? await Task.sleep(for: .seconds(Motion.fadeDuration + 0.03))
                hero.clearBackdropFade(fade.id)
            }
    }
}

// MARK: Full-window cover

struct ArtViewerRequest: Equatable {
    let albumID: PersistentID
    /// The header art's window frame, so the cover grows out of it; nil grows from the centre.
    let from: CGRect?
}

/// An album cover filling the window on a black backdrop, at its own proportions and full resolution.
/// Grows out of the album page's header art and shrinks back into it. Click or Esc closes.
struct ArtViewerOverlay: View {
    @Environment(AppNavigator.self) private var navigator
    @Environment(ArtworkCache.self) private var artwork
    @State private var origin = FrameProbe()
    @State private var shown: ArtViewerRequest?
    @State private var expanded = false
    @State private var image: NSImage?

    var body: some View {
        GeometryReader { proxy in
            if let request = shown {
                let base = origin.windowRect?.origin ?? .zero
                let source = request.from?.offsetBy(dx: -base.x, dy: -base.y) ?? Self.centred(side: 120, in: proxy.size)
                let rect = expanded ? fitted(in: proxy.size) : source
                ZStack(alignment: .topLeading) {
                    Color.black.opacity(expanded ? 0.9 : 0)
                    cover(request.albumID)
                        .frame(width: rect.width, height: rect.height)
                        .clipShape(RoundedRectangle(cornerRadius: expanded ? 6 : 12, style: .continuous))
                        .shadow(color: .black.opacity(0.5), radius: expanded ? 40 : 10, y: 10)
                        .offset(x: rect.minX, y: rect.minY)
                }
                .contentShape(Rectangle())
                .onTapGesture { navigator.artViewer = nil }
                .overlay {
                    // Esc closes; invisible because the whole view already closes on click.
                    Button("Close") { navigator.artViewer = nil }
                        .keyboardShortcut(.cancelAction)
                        .opacity(0)
                }
            }
        }
        .background { Color.clear.frameProbe(origin) }
        .ignoresSafeArea()
        .allowsHitTesting(shown != nil)
        .onChange(of: navigator.artViewer) { _, request in
            if let request { open(request) } else { close() }
        }
    }

    @ViewBuilder
    private func cover(_ albumID: PersistentID) -> some View {
        if let image {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            ArtworkView(albumID: albumID, size: .large, cornerRadius: 0)
        }
    }

    /// The cover's own proportions, as large as fits with a margin.
    private func fitted(in size: CGSize) -> CGRect {
        let aspect = image.map { $0.size.width / max($0.size.height, 1) } ?? 1
        let available = CGSize(width: max(size.width - 80, 100), height: max(size.height - 80, 100))
        var width = available.width
        var height = width / aspect
        if height > available.height {
            height = available.height
            width = height * aspect
        }
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private static func centred(side: CGFloat, in size: CGSize) -> CGRect {
        CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
    }

    private func open(_ request: ArtViewerRequest) {
        image = artwork.cachedImage(album: request.albumID, size: .full)
            ?? artwork.cachedImage(album: request.albumID, size: .large)
            ?? artwork.cachedImage(album: request.albumID, size: .thumbnail)
        expanded = false
        shown = request
        Task { @MainActor in
            withAnimation(Motion.morphOpen) { expanded = true }
            // Swap in the full-resolution image once it's decoded.
            if let full = await artwork.image(album: request.albumID, size: .full), shown == request {
                image = full
            }
        }
    }

    private func close() {
        withAnimation(Motion.morphClose) {
            expanded = false
        } completion: {
            if navigator.artViewer == nil {
                shown = nil
                image = nil
            }
        }
    }
}
