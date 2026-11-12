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
            ArtworkBackdrop(albumID: albumID)
        }
    }
}

extension View {
    /// Album and artist pages keep the window toolbar (it holds the window controls) but empty and
    /// see-through: no background, no title, no system back button. A toolbar over cover colours either
    /// stuck out or couldn't be read; the page shows its own title and brings its own buttons.
    func coverPageChrome() -> some View {
        toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar(removing: .title)
            .navigationBarBackButtonHidden(true)
    }

    /// Clicking the cover shows it full-window, growing out of `probe`'s view. Albums without artwork do
    /// nothing: a full-window placeholder isn't worth seeing.
    func coverViewerOnClick(_ album: Album, from probe: FrameProbe) -> some View {
        modifier(CoverViewerClick(album: album, probe: probe))
    }

    /// Room at the top for the page's own back (and info) buttons above the header.
    func coverPageContentPadding() -> some View {
        padding(.horizontal, 28)
            .padding(.bottom, 28)
            .padding(.top, 62)
    }
}

private struct CoverViewerClick: ViewModifier {
    let album: Album
    let probe: FrameProbe
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigator.self) private var navigator

    func body(content: Content) -> some View {
        let hasArtwork = library.snapshot.hasArtwork(album)
        content
            .onTapGesture {
                guard hasArtwork else { return }
                navigator.artViewer = ArtViewerRequest(albumID: album.id, from: probe.windowRect)
            }
            .pointerStyle(hasArtwork ? .link : nil)
            .help(hasArtwork ? "View Cover" : "")
    }
}

/// The back button for pages shown without a toolbar back button (album and artist pages).
struct PageBackButton: View {
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        if navigator.canGoBack {
            PageCornerButton(symbol: "chevron.left", help: "Back (⌘[)") { navigator.goBack() }
        }
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

struct CoverPageTopBar<Art: View>: View {
    let title: String
    /// 0 with the header in view, 1 once it has scrolled away (see `collapse(scrollOffset:)`).
    let collapse: ScrollCollapse
    let palette: ArtworkPalette?
    @ViewBuilder let art: () -> Art

    /// How far through the header the page has scrolled, for `progress`: the bar fades in as the header's
    /// title passes under it.
    static func collapse(scrollOffset y: CGFloat) -> Double {
        Double(min(max((y - 140) / 80, 0), 1))
    }

    var body: some View {
        let progress = collapse.progress
        HStack(spacing: 12) {
            PageBackButton()
            HStack(spacing: 10) {
                art()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(palette?.primary.color ?? Color.primary)
            }
            .opacity(progress)
            .offset(y: (1 - progress) * 8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .bottom) {
                Rectangle().fill(.bar)
                if let palette { palette.background.color.opacity(0.55) }
                Divider()
            }
            .ignoresSafeArea(edges: .top)
            .opacity(progress)
        }
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

/// A small glass circle button in a page corner, standing in for a toolbar button.
struct PageCornerButton: View {
    let symbol: String
    let help: String
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? Color.accentColor : .primary)
                .frame(width: 34, height: 34)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .beatGlass(in: Circle(), interactive: true)
        .help(help)
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
            Color(nsColor: .windowBackgroundColor)
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
    /// The cover's colours, from `CoverTint` (the same source as the sidebar), once they're this page's.
    /// Nil shows the standard look: Plain in Settings, or still settling.
    private var palette: ArtworkPalette? {
        navigator.coverTint.current.flatMap { $0.route == .album(albumID) ? $0.palette : nil }
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
            CoverPageTopBar<EmptyView>.collapse(scrollOffset: $0.contentOffset.y + $0.contentInsets.top)
        } action: { _, progress in collapse.progress = progress }
        .opacity(revealed ? 1 : 0)
        .background {
            CoverPageBackground(albumID: album.id, palette: palette, shown: backgroundShown)
                .frameProbe(pageProbe)
        }
        .overlay(alignment: .top) {
            CoverPageTopBar(title: album.title, collapse: collapse, palette: palette) {
                ArtworkView(albumID: album.id, cornerRadius: 0)
            }
        }
        // Controls, glass and menus follow the cover's lightness rather than the system's, once its colours show.
        // The page only, not the toolbar: the grid's search field kept this page's scheme after going back.
        .environment(\.colorScheme, backgroundShown ? palette.map { $0.isDark ? ColorScheme.dark : .light } ?? colorScheme : colorScheme)
        .coverPageChrome()
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
        HStack(alignment: .bottom, spacing: 24) {
            ArtworkView(albumID: album.id, size: .large, cornerRadius: 12)
                .frame(width: 230, height: 230)
                .frameProbe(artProbe)
                // Drawn from the outline: SwiftUI's `.shadow` was redrawn on every scrolled frame.
                .background(ShapeShadow(shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
                                        opacity: 0.3, radius: 20, y: 10))
                // Hidden while the zoom's flying copy is on its way here.
                .opacity(hero.isFlying(to: album.id) ? 0 : 1)
                .coverViewerOnClick(album, from: artProbe)

            VStack(alignment: .leading, spacing: 6) {
                Text(album.title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(palette?.primary.color ?? Color.primary)
                    .lineLimit(2)
                Text(album.artist)
                    .font(.title2)
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
        .padding(8)
        .beatGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous), tint: palette?.background.color)
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

struct TrackRow: View {
    let track: Track
    var showArtist = false
    /// The album page's cover colours, when it has them.
    var palette: ArtworkPalette?
    /// Double-click, or Space/Return while the keyboard highlight is on this row.
    var play: () -> Void = {}
    @Environment(PlaybackQueue.self) private var queue
    @Environment(\.gridItem) private var gridItem
    @Environment(\.playbackAccent) private var playbackAccent
    @State private var hovering = false

    private var secondaryStyle: AnyShapeStyle {
        palette.map { AnyShapeStyle($0.secondary.color) } ?? AnyShapeStyle(.secondary)
    }

    var body: some View {
        let isCurrent = queue.current?.id == track.id
        HStack(spacing: 14) {
            Group {
                if isCurrent {
                    PlayingIndicator(isAnimating: queue.isPlaying, color: palette?.primary.color ?? playbackAccent)
                } else {
                    Text(track.trackNumber > 0 ? "\(track.trackNumber)" : "–")
                        .foregroundStyle(palette.map { AnyShapeStyle($0.secondary.color) } ?? AnyShapeStyle(.tertiary))
                }
            }
            .font(.callout.monospacedDigit())
            .frame(width: 26, alignment: .trailing)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(rowFill(isCurrent: isCurrent), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .keyboardHighlight(gridItem.highlighted, cornerRadius: 6)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2, perform: play)
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
