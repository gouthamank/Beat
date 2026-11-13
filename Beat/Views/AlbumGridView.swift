import SwiftUI

struct AlbumGridView: View {
    @Environment(\.pageInset) private var pageInset
    let title: String
    let albums: [Album]
    /// The sidebar page whose search and scroll this grid remembers; nil for pushed pages.
    var memory: SidebarItem?

    @State private var localSearch = ""
    @State private var scrolling = ScrollActivity()
    private static let tile = (minimum: 160.0, spacing: 22.0)
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigator.self) private var navigator

    private var search: String { navigator.search(memory, else: $localSearch).wrappedValue }

    private var visible: [Album] { library.snapshot.albums(albums, matching: search) }

    var body: some View {
        let shown = visible
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.tile.minimum, maximum: 220), spacing: Self.tile.spacing)], spacing: 26) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, album in
                    AlbumTile(album: album).keyboardGridItem(i)
                }
            }
            .padding(pageInset)
            .pausesPointerWhileScrolling(scrolling)
        }
        .tracksScrolling(scrolling)
        .remembersScroll(memory)
        // Outside the scroll modifiers: it wraps the scroll view in a reader.
        .keyboardGrid(count: shown.count, layout: .adaptive(minimum: Self.tile.minimum, spacing: Self.tile.spacing, inset: pageInset),
                      id: { shown[$0].id })
        .navigationTitle(title)
        .pageSubtitle(albums.count.counted("album") + albums.reduce(0) { $0 + $1.fileSize }.fileSizeSuffix)
        .searchable(text: navigator.search(memory, else: $localSearch), placement: .page, prompt: "Albums")
    }
}

/// An album cover with title. Clicking opens the album page, zooming the cover into its header.
struct AlbumTile: View {
    let album: Album
    /// Off where a heading already names the artist (Songs' album-artist sections).
    var showsArtist = true
    /// Off shows the cover alone (an element's Show footer setting).
    var showsFooter = true
    @Environment(LibraryStore.self) private var library
    @Environment(PlaybackQueue.self) private var queue
    @Environment(AppNavigator.self) private var navigator
    @Environment(HeroTransition.self) private var hero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.albumNavigationDisabled) private var navigationDisabled
    @Environment(\.gridItem) private var gridItem
    @State private var hovering = false
    @State private var probe = FrameProbe()
    /// Clicked: keeps the probe until the zoom has measured it.
    @State private var armed = false

    /// Only a tile that might start or receive a zoom carries the AppKit probe (see HeroTransition.lastOpened).
    private var needsProbe: Bool { hovering || armed || gridItem.highlighted || hero.lastOpened == .album(album.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(albumID: album.id, cornerRadius: 10)
                .background { if needsProbe { Color.clear.frameProbe(probe) } }
                .zoomSource(.album(album.id))
                .keyboardHighlight(gridItem.highlighted, cornerRadius: 10)
                .opacity(hero.isReturning(to: album.id) ? 0 : 1)
                // Drawn from the outline: SwiftUI's `.shadow` was redrawn for every tile on every scrolled frame.
                .background(ShapeShadow(shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                                        opacity: hovering ? 0.3 : 0.15, radius: hovering ? 14 : 6, y: hovering ? 8 : 3))
                .overlay(alignment: .bottomTrailing) {
                    if hovering {
                        Button { queue.play(library.snapshot.tracks(of: album)) } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .beatGlass(in: Circle(), interactive: true)
                        .padding(10)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .scaleEffect(hovering ? 1.03 : 1)
            if showsFooter {
                Text(album.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if showsArtist {
                    Text(album.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
        // A tap gesture rather than a Button, so the hover play button inside stays its own control.
        .onTapGesture(perform: open)
        .onChange(of: gridItem.activation) { _, serial in if serial != nil { open() } }
        .onChange(of: gridItem.highlighted) { _, on in if on, !navigationDisabled { navigator.coverTint.prefetch(.album(album.id)) } }
        .accessibilityAddTraits(.isButton)
        .contextMenu {
            let tracks = library.snapshot.tracks(of: album)
            TrackContextMenu(tracks: tracks)
            Button("Shuffle", systemImage: "shuffle") { queue.play(tracks, shuffled: true) }
        }
        .onHover { h in
            withAnimation(.spring(duration: 0.25)) { hovering = h }
            // Pointer on the tile: its page's colours are usually ready before the click.
            if h, !navigationDisabled { navigator.coverTint.prefetch(.album(album.id)) }
        }
        .task(id: album.id) { hero.registerTile(probe, for: album.id, cornerRadius: 10) }
    }

    private func open() {
        guard !navigationDisabled else { return }
        armed = true
        navigator.openWhenReady(.album(album.id)) {
            hero.open(album.id, from: probe, cornerRadius: 10, navigator: navigator, reduceMotion: reduceMotion)
        }
    }
}
