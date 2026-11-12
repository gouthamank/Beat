import SwiftUI

// MARK: Artists

struct ArtistGridView: View {
    let title: String
    let artists: [Artist]
    /// The sidebar page whose search and scroll this grid remembers; nil for pushed pages.
    var memory: SidebarItem?
    @State private var localSearch = ""
    @State private var scrolling = ScrollActivity()
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        let searchText = navigator.search(memory, else: $localSearch)
        let search = searchText.wrappedValue
        let visible = search.isEmpty ? artists : artists.filter { $0.name.localizedCaseInsensitiveContains(search) }
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 170), spacing: 22)], spacing: 26) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { i, artist in
                    ArtistTile(artist: artist).keyboardGridItem(i)
                }
            }
            .padding(24)
            .pausesPointerWhileScrolling(scrolling)
        }
        .tracksScrolling(scrolling)
        .remembersScroll(memory)
        .keyboardGrid(count: visible.count, layout: .adaptive(minimum: 130, spacing: 22, inset: 24), id: { visible[$0].id })
        .navigationTitle(title)
        .navigationSubtitle("\(artists.count.counted("artist")) · \(artists.reduce(0) { $0 + $1.fileSize }.fileSizeText)")
        .searchable(text: searchText, placement: .toolbar, prompt: "Artists")
    }
}

struct ArtistTile: View {
    let artist: Artist
    /// Off shows the art alone (an element's Show footer setting).
    var showsFooter = true
    @Environment(AppNavigator.self) private var navigator
    @Environment(HeroTransition.self) private var hero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.albumNavigationDisabled) private var navigationDisabled
    @Environment(\.gridItem) private var gridItem
    @State private var hovering = false
    @State private var probe = FrameProbe()
    @State private var armed = false

    /// Only a tile that might start or receive a zoom carries the AppKit probe (see HeroTransition.lastOpened).
    private var needsProbe: Bool { hovering || armed || gridItem.highlighted || hero.lastOpened == .artist(artist.id) }

    var body: some View {
        // A tap gesture, as on album tiles.
        VStack(spacing: 8) {
            ArtistArtwork(albumIDs: artist.albumIDsNewestFirst, artistID: artist.id)
                .background { if needsProbe { Color.clear.frameProbe(probe) } }
                .keyboardHighlight(gridItem.highlighted, cornerRadius: 10)
                .opacity(hero.isReturning(to: .artist(artist.id)) ? 0 : 1)
                .background(ShapeShadow(shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                                        opacity: hovering ? 0.3 : 0.15, radius: hovering ? 12 : 5, y: hovering ? 6 : 3))
                .scaleEffect(hovering ? 1.03 : 1)
            if showsFooter {
                Text(artist.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(artist.albumIDs.count.counted("album"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onChange(of: gridItem.activation) { _, serial in if serial != nil { open() } }
        .onChange(of: gridItem.highlighted) { _, on in if on, !navigationDisabled { navigator.coverTint.prefetch(.artist(artist.id)) } }
        .accessibilityAddTraits(.isButton)
        .onHover { h in
            withAnimation(.spring(duration: 0.25)) { hovering = h }
            if h, !navigationDisabled { navigator.coverTint.prefetch(.artist(artist.id)) }
        }
        .task(id: artist.id) { hero.registerTile(probe, for: .artist(artist.id), cornerRadius: 10) }
    }

    private func open() {
        guard !navigationDisabled else { return }
        armed = true
        navigator.openWhenReady(.artist(artist.id)) {
            hero.open(.artist(artist.id), from: probe, cornerRadius: 10, navigator: navigator, reduceMotion: reduceMotion)
        }
    }
}

// MARK: Genres

struct GenreGridView: View {
    let title: String
    let genres: [Genre]
    /// The sidebar page whose scroll this grid remembers; nil for pushed pages.
    var memory: SidebarItem?

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 20)], spacing: 20) {
                ForEach(Array(genres.enumerated()), id: \.element.id) { i, genre in
                    GenreTile(genre: genre).keyboardGridItem(i)
                }
            }
            .padding(24)
        }
        .remembersScroll(memory)
        .keyboardGrid(count: genres.count, layout: .adaptive(minimum: 170, spacing: 20, inset: 24), id: { genres[$0].id })
        .navigationTitle(title)
        .navigationSubtitle("\(genres.count.counted("genre")) · \(genres.reduce(0) { $0 + $1.fileSize }.fileSizeText)")
    }
}

struct GenreTile: View {
    let genre: Genre
    /// Off shows the art alone, without the name over it (an element's Show footer setting).
    var showsFooter = true
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.albumNavigationDisabled) private var navigationDisabled
    @Environment(\.gridItem) private var gridItem
    @State private var hovering = false

    var body: some View {
        Button { if !navigationDisabled { navigator.openGenre(genre.id) } } label: {
            ArtworkView(albumID: genre.albumIDs.first, cornerRadius: 14)
                .overlay {
                    if showsFooter {
                        LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if showsFooter {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(genre.name).font(.headline).lineLimit(1)
                            Text(genre.trackCount.counted("song")).font(.caption).opacity(0.8)
                        }
                        .foregroundStyle(.white)
                        .padding(12)
                    }
                }
                .keyboardHighlight(gridItem.highlighted, cornerRadius: 14)
                .background(ShapeShadow(shape: RoundedRectangle(cornerRadius: 14, style: .continuous),
                                        opacity: hovering ? 0.3 : 0.15, radius: hovering ? 12 : 5, y: hovering ? 6 : 3))
                .scaleEffect(hovering ? 1.03 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The grid is the Tab stop; tiles aren't, or Tab would walk every genre.
        .focusable(false)
        .onChange(of: gridItem.activation) { _, serial in
            if serial != nil, !navigationDisabled { navigator.openGenre(genre.id) }
        }
        .onHover { h in withAnimation(.spring(duration: 0.25)) { hovering = h } }
    }
}

struct GenreDetailView: View {
    let genreID: String
    @Environment(LibraryStore.self) private var library

    var body: some View {
        if let genre = library.snapshot.genresByID[genreID] {
            AlbumGridView(title: genre.name, albums: genre.albumIDs.compactMap { library.snapshot.albumsByID[$0] })
                .toolbar { PlayShuffleToolbar(tracks: library.snapshot.tracks(of: genre)) }
        } else {
            ContentUnavailableView("Genre Not Found", systemImage: "guitars")
        }
    }
}

// MARK: Shared

struct PlayShuffleToolbar: ToolbarContent {
    let tracks: [Track]
    @Environment(PlaybackQueue.self) private var queue

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Play", systemImage: "play.fill") { queue.play(tracks) }
                .disabled(tracks.isEmpty)
            Button("Shuffle", systemImage: "shuffle") { queue.play(tracks, shuffled: true) }
                .disabled(tracks.isEmpty)
        }
    }
}
