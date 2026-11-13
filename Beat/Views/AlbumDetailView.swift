import SwiftUI

/// An album page's background: the cover's background colour, a vivid blur of the cover fading in from the
/// top, and a wash of the background over both; or, without cover colours, a soft blur of the cover.
/// Shared with `HeroOverlay`, which fades a copy out as the page leaves.
struct AlbumBackground: View {
    let albumID: PersistentID
    let palette: ArtworkPalette?

    var body: some View {
        if let palette {
            ZStack {
                palette.background.color
                ArtworkBackdrop(albumID: albumID, vividness: .vivid)
                    .mask(LinearGradient(colors: [.black, .black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom))
                // Keeps what's behind the text close to the colour its contrast was checked against.
                palette.background.color.opacity(0.55)
            }
            .transition(.opacity)
        } else {
            #if os(macOS)
            ArtworkBackdrop(albumID: albumID)
            #else
            // Nothing until the colours are worked out. The Mac works them out on hover, so they're usually ready;
            // a touch screen has no hover, and the plain blur of a pale cover flashed white before the colours came.
            Color.clear
            #endif
        }
    }
}

extension View {
    /// Album and artist pages keep the window toolbar but see-through: no background, no title, no system
    /// back button. A toolbar background over cover colours either stuck out or couldn't be read; the page
    /// draws its own tinted bar under the strip (`CoverPageTopBar`) and puts back and its title there as items
    /// (`coverPageToolbar`).
    func coverPageChrome() -> some View {
        #if os(macOS)
        toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar(removing: .title)
            .navigationBarBackButtonHidden(true)
        #else
        // The navigation bar's equivalent: see-through and no system back button. The system title gives way to
        // the compact one, which `coverPageToolbar` puts in the centre. A clear background rather than a hidden one:
        // iOS ignores the bar's colour scheme while its background is hidden, and that scheme sets the status bar.
        toolbarBackground(Color.clear, for: .navigationBar)
            .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            // Hiding back also turned off the back swipe.
            .background { SwipeBackEnabler() }
        #endif
    }

    /// Clicking the cover shows it full-window, growing out of `probe`'s view. Albums without artwork do
    /// nothing: a full-window placeholder isn't worth seeing.
    /// `onAlbumPage`: only while that album's page is the front page. A page swiped away on iPad and iPhone stays on
    /// screen while it shrinks into its tile, and a tap meant for the grid under it opened its cover full screen.
    func coverViewerOnClick(_ album: Album, from probe: FrameProbe, onAlbumPage: Bool = false) -> some View {
        modifier(CoverViewerClick(album: album, probe: probe, onAlbumPage: onAlbumPage))
    }

    /// A cover page header: the art beside its text on the Mac and iPad, stacked and centred on a phone. One
    /// `AnyLayout`, so switching keeps the children's identity.
    func coverPageHeaderLayout<Content: View>(_ compact: Bool, @ViewBuilder content: () -> Content) -> some View {
        let layout = compact ? AnyLayout(VStackLayout(alignment: .center, spacing: 18))
                             : AnyLayout(HStackLayout(alignment: .bottom, spacing: 24))
        return layout(content).frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
    }

    /// The page's margins. The top is small: back and the compact title live in the window toolbar
    /// (`coverPageToolbar`), so the header starts just under it. It used to reserve 62 pt for a back button
    /// floating over the page, below an empty toolbar strip.
    func coverPageContentPadding() -> some View {
        modifier(CoverPageContentPadding())
    }

    /// Back, and the page's art and title fading in as the header scrolls away, as window toolbar items. Apply
    /// after the page's colour-scheme override, which must not reach the toolbar (the grid's search field kept
    /// the page's scheme after going back); `scheme` is applied inside the items instead.
    func coverPageToolbar<Art: View>(title: String, collapse: ScrollCollapse, palette: ArtworkPalette?, scheme: ColorScheme,
                                     @ViewBuilder art: @escaping () -> Art) -> some View {
        toolbar {
            ToolbarItem(placement: .navigation) {
                CoverPageBackButton().environment(\.colorScheme, scheme)
            }
            #if os(macOS)
            ToolbarItem(placement: .navigation) {
                CoverPageToolbarTitle(title: title, collapse: collapse, palette: palette, art: art)
                    .environment(\.colorScheme, scheme)
            }
            #else
            // In the centre, without a glass pill: beside back, it shared back's pill, which clipped the title to a
            // few letters.
            ToolbarItem(placement: .principal) {
                CoverPageToolbarTitle(title: title, collapse: collapse, palette: palette, art: art)
                    .environment(\.colorScheme, scheme)
            }
            .sharedBackgroundVisibility(.hidden)
            #endif
        }
        #if os(iOS)
        // The status bar follows the cover's lightness here; the window keeps the system's (see `RootView`).
        .toolbarColorScheme(scheme, for: .navigationBar)
        #endif
    }
}

private struct CoverViewerClick: ViewModifier {
    let album: Album
    let probe: FrameProbe
    let onAlbumPage: Bool
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigator.self) private var navigator
    /// When the album page appeared: a tap repeated because the first seemed slow (the page waits briefly for its
    /// colours) landed on the newly opened page's cover and opened it full screen.
    @State private var appeared = Date.distantPast

    func body(content: Content) -> some View {
        let hasArtwork = library.snapshot.hasArtwork(album)
        content
            .onTapGesture {
                guard hasArtwork else { return }
                if onAlbumPage {
                    guard navigator.path.last == .album(album.id), Date.now.timeIntervalSince(appeared) > 0.5 else { return }
                }
                navigator.artViewer = ArtViewerRequest(albumID: album.id, from: probe.windowRect)
            }
            .onAppear { appeared = .now }
            .linkPointer(hasArtwork)
            .help(hasArtwork ? "View Cover" : "")
    }
}

/// Back on album and artist pages, which hide the system back button (see `coverPageChrome`).
private struct CoverPageBackButton: View {
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        if navigator.canGoBack {
            Button { navigator.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                .help("Back (⌘[)")
        }
    }
}

/// The page's art and title in the toolbar, fading in as the header's title scrolls under it.
private struct CoverPageToolbarTitle<Art: View>: View {
    let title: String
    let collapse: ScrollCollapse
    let palette: ArtworkPalette?
    @ViewBuilder let art: () -> Art

    var body: some View {
        let progress = collapse.progress
        HStack(spacing: 8) {
            art()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .foregroundStyle(palette?.primary.color ?? Color.primary)
        }
        .opacity(progress)
        .offset(y: (1 - progress) * 6)
        .allowsHitTesting(false)
        .accessibilityHidden(progress < 0.5)
    }
}

/// The top of an album or artist page: the back button, and, as the header scrolls away, a compact bar
/// with the page's art and title fading in behind it. The bar's blurred, cover-tinted background also stops
/// scrolled content from colliding with the back button.
/// How far an album or artist page's header has scrolled away. Its own object, read only by the top bar,
/// so scrolling through the header updates the bar without re-rendering the whole page.
@MainActor
@Observable
final class ScrollCollapse {
    var progress = 0.0
}

/// Behind the toolbar strip on album and artist pages: clear while the header shows, a blurred, cover-tinted bar
/// once it has scrolled away, so content scrolling under the strip doesn't collide with back and the title.
/// The toolbar's own background stays hidden (see `coverPageChrome`); this is drawn by the page, under it.
struct CoverPageTopBar: View {
    let collapse: ScrollCollapse
    let palette: ArtworkPalette?

    /// How far through the header the page has scrolled, for `progress`: the bar fades in as the header's
    /// title passes under the toolbar.
    static func collapse(scrollOffset y: CGFloat) -> Double {
        Double(min(max((y - 94) / 80, 0), 1))
    }

    var body: some View {
        // A zero-height anchor just under the strip, with the bar as its background: a background ignoring the top
        // safe area grows up over exactly the strip. (A fixed zero-height frame of its own stays zero and showed
        // nothing; content then ran visibly under the title.)
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 0)
            .background(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    Rectangle().fill(.bar)
                    if let palette { palette.background.color.opacity(0.55) }
                    Divider()
                }
                .ignoresSafeArea(edges: .top)
                .opacity(collapse.progress)
            }
            .allowsHitTesting(false)
    }
}

/// A grey block standing in for content that's still loading, with a light sweeping across it.
struct ShimmerBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.primary.opacity(0.1))
            .frame(width: width, height: height)
            .modifier(Shimmer())
    }
}

private struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.5)
                        .offset(x: phase * proxy.size.width)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.5 }
            }
    }
}

/// An album or artist page's background: an opaque window-coloured base with the cover backdrop fading
/// over it. The base matters: while the backdrop fades in or changes from plain to coloured, neither layer
/// is fully opaque, and without it the page underneath showed through for a few frames.
struct CoverPageBackground: View {
    let albumID: PersistentID?
    let palette: ArtworkPalette?
    let shown: Bool

    var body: some View {
        ZStack {
            #if os(macOS)
            Color.windowBackground
            #else
            // The cover's own colour under the backdrop while it fades in. The window turns light with a pale cover
            // at once, so the plain background flashed white over a dark system appearance.
            palette?.background.color ?? Color.windowBackground
            #endif
            if let albumID {
                WindowAlignedAlbumBackground(albumID: albumID, palette: palette)
                    .opacity(shown ? 1 : 0)
            }
        }
        .ignoresSafeArea()
    }
}

/// `AlbumBackground` drawn as if it covered the whole window, showing only the part under this view. The
/// album page and the sidebar both draw one, so the cover's blur runs on across the divider instead of
/// starting again in each column; the columns are hosted separately, so they can't share a single view.
struct WindowAlignedAlbumBackground: View {
    let albumID: PersistentID
    let palette: ArtworkPalette?
    @State private var probe = FrameProbe()
    @State private var origin: CGPoint?
    @State private var window: CGSize?

    var body: some View {
        GeometryReader { proxy in
            if let origin, let window {
                AlbumBackground(albumID: albumID, palette: palette)
                    .frame(width: window.width, height: window.height)
                    .offset(x: -origin.x, y: -origin.y)
            } else {
                AlbumBackground(albumID: albumID, palette: palette)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .clipped()
        .background { Color.clear.frameProbe(probe) }
        // Moving matters as much as resizing: the artist info sidebar slides in and out, shifting the
        // slices beside it without always changing their size.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { _ in remeasure() }
        .task { remeasure() }
    }

    /// Measures now, and again once the window has laid out the change; the probe's AppKit frame can
    /// trail SwiftUI's layout by a pass.
    private func remeasure() {
        measure()
        Task { @MainActor in
            await Task.yield()
            measure()
        }
    }

    private func measure() {
        guard let rect = probe.windowRect, let size = probe.windowSize else { return }
        if origin != rect.origin { origin = rect.origin }
        if window != size { window = size }
    }
}

struct AlbumDetailView: View {
    let albumID: PersistentID
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackQueue.self) private var queue
    @Environment(ArtworkCache.self) private var artwork
    @Environment(HeroTransition.self) private var hero
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.compactLayout) private var compact
    /// The cover's colours, from `CoverTint` (the same source as the sidebar), once they're this page's.
    /// Nil shows the standard look: Plain in Settings, or still settling.
    private var palette: ArtworkPalette? {
        navigator.coverTint.current.flatMap { $0.route == .album(albumID) ? $0.palette : nil }
    }
    /// The cover's lightness once its colours show, else the system's: for the page and its toolbar items.
    private var pageScheme: ColorScheme {
        backgroundShown ? palette.map { $0.isDark ? ColorScheme.dark : .light } ?? colorScheme : colorScheme
    }
    @State private var artProbe = FrameProbe()
    /// False while an album zoom is landing, so the page fades in around the flying cover.
    @State private var revealed = false
    /// The cover colours fade in whenever this page comes to the front (and out via `HeroOverlay` as it leaves).
    @State private var backgroundShown = false
    /// The whole page, measured so the departing colours can be drawn over the same area.
    @State private var pageProbe = FrameProbe()
    /// How far the header has scrolled away, for the compact top bar.
    @State private var collapse = ScrollCollapse()
    @State private var scrolling = ScrollActivity()

    var body: some View {
        if let album = library.snapshot.albumsByID[albumID] {
            content(album, tracks: library.snapshot.tracks(of: album))
        } else {
            ContentUnavailableView("Album Not Found", systemImage: "square.stack")
        }
    }

    private func content(_ album: Album, tracks: [Track]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(album, tracks: tracks)
                trackList(album, tracks: tracks)
            }
            .coverPageContentPadding()
            // Full width from the start, so nothing centres while it's narrower than the page.
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
            .followsKeyboardHighlight()
            // Each track row has hover and tap handlers, and checking them all on every scrolled frame was a
            // fifth of the main thread's work while scrolling.
            .pausesPointerWhileScrolling(scrolling)
        }
        .tracksScrolling(scrolling)
        .onScrollGeometryChange(for: Double.self) {
            CoverPageTopBar.collapse(scrollOffset: $0.contentOffset.y + $0.contentInsets.top)
        } action: { _, progress in collapse.progress = progress }
        .opacity(revealed ? 1 : 0)
        .background {
            CoverPageBackground(albumID: album.id, palette: palette, shown: backgroundShown)
                .frameProbe(pageProbe)
        }
        .overlay(alignment: .top) { CoverPageTopBar(collapse: collapse, palette: palette) }
        // Controls, glass and menus follow the cover's lightness rather than the system's, once its colours show.
        // The page only, not the toolbar: the grid's search field kept this page's scheme after going back.
        .environment(\.colorScheme, pageScheme)
        .coverPageChrome()
        .coverPageToolbar(title: album.title, collapse: collapse, palette: palette, scheme: pageScheme) {
            ArtworkView(albumID: album.id, cornerRadius: 0)
        }
        .navigationTitle(album.title)
        .onAppear {
            hero.setTarget(artProbe, for: album.id)
            hero.setPage(pageProbe, for: album.id)
            if hero.isFlying(to: album.id) {
                withAnimation(Motion.fade) { revealed = true }
            } else {
                revealed = true
            }
            withAnimation(Motion.fade) { backgroundShown = true }
        }
        // Covered by a pushed page: fade back in when it comes to the front again.
        .onDisappear { backgroundShown = false }
    }

    private func header(_ album: Album, tracks: [Track]) -> some View {
        // A row beside the cover, or on a phone stacked under it. One layout either way, so the probed cover keeps
        // its identity (see the FrameProbe gotcha).
        coverPageHeaderLayout(compact) {
            ArtworkView(albumID: album.id, size: .large, cornerRadius: 12)
                .frame(width: compact ? 240 : 230, height: compact ? 240 : 230)
                .frameProbe(artProbe)
                // Drawn from the outline: SwiftUI's `.shadow` was redrawn on every scrolled frame.
                .background(ShapeShadow(shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                        opacity: 0.3, radius: 20, y: 10))
                // Hidden while the zoom's flying copy is on its way here.
                .opacity(hero.isFlying(to: album.id) ? 0 : 1)
                .coverViewerOnClick(album, from: artProbe, onAlbumPage: true)

            VStack(alignment: compact ? .center : .leading, spacing: 6) {
                Text(album.title)
                    .font(compact ? .title.bold() : .largeTitle.bold())
                    .foregroundStyle(palette?.primary.color ?? Color.primary)
                    .lineLimit(compact ? 3 : 2)
                Text(album.artist)
                    .font(compact ? .title3 : .title2)
                    .foregroundStyle(palette.map { AnyShapeStyle($0.secondary.color) } ?? AnyShapeStyle(.secondary))
                Text(metadataLine(album, trackCount: tracks.count))
                    .font(.callout)
                    .foregroundStyle(palette.map { AnyShapeStyle($0.secondary.color) } ?? AnyShapeStyle(.tertiary))

                BeatGlassContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button { queue.play(tracks) } label: { Label("Play", systemImage: "play.fill").frame(minWidth: 70) }
                            .beatGlassButtonStyle(prominent: true)
                        Button { queue.play(tracks, shuffled: true) } label: { Label("Shuffle", systemImage: "shuffle").frame(minWidth: 70) }
                            .beatGlassButtonStyle()
                    }
                    .controlSize(.large)
                }
                .padding(.top, 10)
            }
            .multilineTextAlignment(compact ? .center : .leading)
        }
    }

    private func trackList(_ album: Album, tracks: [Track]) -> some View {
        let showDiscs = album.discCount > 1
        let discs = Dictionary(grouping: tracks, by: \.discNumber).sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(discs, id: \.key) { disc, discTracks in
                if showDiscs {
                    Text("Disc \(disc)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                }
                ForEach(discTracks) { track in
                    let index = tracks.firstIndex(of: track) ?? 0
                    // On a phone, a plain list with separators (inset to the titles) in place of the card.
                    if compact, track.id != discTracks.first?.id {
                        Divider().padding(.leading, TrackRow.compactTitleInset)
                    }
                    TrackRow(track: track, showArtist: track.displayArtist != album.artist, palette: palette) {
                        queue.play(tracks, startAt: index)
                    }
                    .contextMenu { TrackContextMenu(tracks: [track]) }
                    .keyboardGridItem(index)
                }
            }
        }
        // One column: up and down move through the songs, Space or Return plays.
        .keyboardGrid(count: tracks.count, layout: .order(.columns(rows: tracks.count)), id: { tracks[$0].id })
        .modifier(TrackListCard(compact: compact, tint: palette?.background.color))
    }

    private func metadataLine(_ album: Album, trackCount: Int) -> String {
        var parts: [String] = []
        if !album.genre.isEmpty { parts.append(album.genre) }
        if album.year > 0 { parts.append(String(album.year)) }
        parts.append(trackCount.counted("song"))
        parts.append(Duration.seconds(album.duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
        if album.fileSize > 0 { parts.append(album.fileSize.fileSizeText) }
        return parts.joined(separator: " · ")
    }
}

/// The track list's glass card on the Mac and iPad. On a phone the rows go without: the card's padding, the row's
/// and the page margin together took ~36 pt from each side of a ~375 pt screen.
private struct TrackListCard: ViewModifier {
    let compact: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        if compact {
            content
        } else {
            content
                .padding(8)
                .beatGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), tint: tint)
        }
    }
}

struct TrackRow: View {
    /// Where a phone's titles start, for separators that line up with them: number column, gap and row padding.
    static let compactTitleInset: CGFloat = 4 + 20 + 10

    let track: Track
    var showArtist = false
    /// The album page's cover colours, when it has them.
    var palette: ArtworkPalette?
    /// Double-click, or Space/Return while the keyboard highlight is on this row.
    var play: () -> Void = {}
    @Environment(PlaybackQueue.self) private var queue
    @Environment(\.gridItem) private var gridItem
    @Environment(\.playbackAccent) private var playbackAccent
    @Environment(\.compactLayout) private var compact
    @State private var hovering = false

    private var secondaryStyle: AnyShapeStyle {
        palette.map { AnyShapeStyle($0.secondary.color) } ?? AnyShapeStyle(.secondary)
    }

    var body: some View {
        let isCurrent = queue.current?.id == track.id
        HStack(spacing: compact ? 10 : 14) {
            Group {
                if isCurrent {
                    PlayingIndicator(isAnimating: queue.isPlaying, color: palette?.primary.color ?? playbackAccent)
                } else {
                    Text(track.trackNumber > 0 ? "\(track.trackNumber)" : "–")
                        .foregroundStyle(palette.map { AnyShapeStyle($0.secondary.color) } ?? AnyShapeStyle(.tertiary))
                }
            }
            .font(.callout.monospacedDigit())
            .frame(width: compact ? 20 : 26, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).lineLimit(1)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(palette?.primary.color ?? Color.primary)
                if showArtist {
                    Text(track.displayArtist).font(.caption).foregroundStyle(secondaryStyle).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            Text(track.duration.trackTime)
                .font(.callout.monospacedDigit())
                .foregroundStyle(secondaryStyle)
        }
        // A phone's rows are a little taller (easier to tap) and barely padded at the sides (no card around them).
        .padding(.horizontal, compact ? 4 : 12)
        .padding(.vertical, compact ? 11 : 8)
        .background(rowFill(isCurrent: isCurrent), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .keyboardHighlight(gridItem.highlighted, cornerRadius: 6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Double-click plays on the Mac (a click selects nothing here, but it's the Mac's convention); a tap on touch.
        #if os(macOS)
        .onTapGesture(count: 2, perform: play)
        #else
        .onTapGesture(perform: play)
        #endif
        .onChange(of: gridItem.activation) { _, serial in if serial != nil { play() } }
    }

    private func rowFill(isCurrent: Bool) -> AnyShapeStyle {
        if isCurrent { return AnyShapeStyle((palette?.primary.color ?? playbackAccent).opacity(hovering ? 0.22 : 0.16)) }
        return AnyShapeStyle(.primary.opacity(hovering ? 0.06 : 0))
    }
}

extension TimeInterval {
    /// "3:07" or "1:02:45".
    var trackTime: String {
        let total = Int(self.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

extension Int {
    /// "1 album", "3 albums", "20,000 songs": the count with its noun, singular for exactly one.
    func counted(_ singular: String, _ plural: String? = nil) -> String {
        "\(formatted()) \(self == 1 ? singular : plural ?? singular + "s")"
    }
}

extension Int64 {
    /// Bytes as Finder shows a file's size: "412 MB", "41.2 GB".
    var fileSizeText: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }

    /// " · 41.2 GB" to follow a count, or nothing when no size is known: MediaPlayer reports none on iPad and
    /// iPhone, and every page read "0 KB".
    var fileSizeSuffix: String { self > 0 ? " · \(fileSizeText)" : "" }
}

/// "Play Next" / "Add to Queue" for any set of tracks.
struct TrackContextMenu: View {
    let tracks: [Track]
    @Environment(PlaybackQueue.self) private var queue

    var body: some View {
        Button("Play", systemImage: "play") { queue.play(tracks) }
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { queue.playNext(tracks) }
        Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { queue.addToQueue(tracks) }
    }
}

/// The cover pages' margins: narrower on a phone, where 28 pt a side took a seventh of the screen.
private struct CoverPageContentPadding: ViewModifier {
    @Environment(\.compactLayout) private var compact

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, compact ? 16 : 28)
            .padding(.bottom, 28)
            .padding(.top, 16)
    }
}
