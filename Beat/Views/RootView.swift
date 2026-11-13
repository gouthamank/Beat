import SwiftUI

enum SidebarItem: Hashable {
    case page(UUID)
    case albums, artists, songs, genres

    /// "page:<uuid>" or the Library page's name, for saving the selection between launches.
    var storageString: String {
        switch self {
        case .page(let id): "page:\(id.uuidString)"
        case .albums: "albums"
        case .artists: "artists"
        case .songs: "songs"
        case .genres: "genres"
        }
    }

    init?(storageString: String) {
        if storageString.hasPrefix("page:") {
            guard let id = UUID(uuidString: String(storageString.dropFirst(5))) else { return nil }
            self = .page(id)
        } else if let library = LibraryPage(rawValue: storageString) {
            self = library.item
        } else {
            return nil
        }
    }
}

/// The built-in Library pages, in sidebar order. Any of them can be hidden in Settings.
enum LibraryPage: String, CaseIterable, Identifiable {
    case albums, artists, songs, genres

    /// Stored as a comma-separated list of hidden pages, so pages added later show by default.
    static let hiddenKey = "library.hidden"

    var id: Self { self }

    var title: String {
        switch self {
        case .albums: "Albums"
        case .artists: "Artists"
        case .songs: "Songs"
        case .genres: "Genres"
        }
    }

    var symbol: String {
        switch self {
        case .albums: "square.stack"
        case .artists: "music.microphone"
        case .songs: "music.note"
        case .genres: "guitars"
        }
    }

    var item: SidebarItem {
        switch self {
        case .albums: .albums
        case .artists: .artists
        case .songs: .songs
        case .genres: .genres
        }
    }

    init?(_ item: SidebarItem?) {
        guard let page = Self.allCases.first(where: { $0.item == item }) else { return nil }
        self = page
    }

    static func hidden(in stored: String) -> Set<LibraryPage> {
        Set(stored.split(separator: ",").compactMap { LibraryPage(rawValue: String($0)) })
    }

    static func stored(_ hidden: Set<LibraryPage>) -> String {
        allCases.filter(hidden.contains).map(\.rawValue).joined(separator: ",")
    }
}

struct RootView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PageStore.self) private var pages
    @Environment(AppNavigator.self) private var navigator
    @AppStorage(LibraryPage.hiddenKey) private var hiddenLibraryPages = ""
    @AppStorage("appearance.coverColours") private var coverColours = true
    @Environment(PlayHistoryStore.self) private var history
    /// A phone-width window: the sidebar is a drawer over the page rather than a column.
    @Environment(\.compactLayout) private var compact

    private var selection: SidebarItem? { navigator.selection }





    /// The page column beside the sidebar, or on a phone alone (its sidebar is the drawer).
    @ViewBuilder
    private var columns: some View {
        if compact {
            pageStack
        } else {
            NavigationSplitView {
                sidebar.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
            } detail: {
                pageStack
            }
        }
    }

    /// The sidebar list. A pick shows its page and, on a phone, closes the drawer, even when it's the page already
    /// showing.
    private var sidebar: some View {
        SidebarView(selection: Binding(get: { navigator.selection }, set: { item in
            navigator.selection = item
            navigator.sidebarDrawerOpen = false
        }))
    }

    private var pageStack: some View {
        NavigationStack(path: navigator.pathBinding(for: selection)) {
            detail
                .nowPlayingBarSpace()
                .sidebarDrawerButton()
                .navigationDestination(for: Route.self) { route in
                    // Pushed pages are hosted separately and set the window's minimum themselves: without
                    // their own, an album page let the window shrink below the page underneath, which
                    // then overflowed the column and shifted everything sideways.
                    // Opaque, toolbar included: after an album page was pushed over a genre or See All grid and
                    // popped, the page underneath showed through the grid, which draws no background itself.
                    destination(route).zoomDestination(route).nowPlayingBarSpace().frame(minWidth: pageColumnMinWidth)
                        .background(Color.windowBackground.ignoresSafeArea())
                }
        }
        .id(selection)
        .zoomTransitions()
        // Where the window's now-playing bar goes (see WindowNowPlayingBar).
        .background { DetailColumnReader(navigator: navigator) }
        // The window's minimum width lives here, not on the window's root view: a root `minWidth` cut
        // the sidebar's expand animation short (the page slid halfway, then snapped).
        .frame(minWidth: pageColumnMinWidth)
    }

    /// The sidebar, the page column and the window's now-playing bar. Split out of `body`, which grew too
    /// long for the compiler to type-check in reasonable time.
    private var splitView: some View {
        columns
        // One bar for the window, above pushed pages. Before `.disabled`, so it's disabled with the rest of the
        // window behind full-window views, and before the overlays that must draw over it.
        .overlay { WindowNowPlayingBar() }
        // On a phone, over the bar too, like the page it covers.
        .sidebarDrawer { sidebar }
        // Full-window views cover the window, so Tab (and VoiceOver) must stay inside them rather than
        // reach the sidebar and page underneath.
        .disabled(navigator.showingNowPlaying || navigator.artViewer != nil)
        .accessibilityHidden(navigator.showingNowPlaying || navigator.artViewer != nil)
        .onChange(of: navigator.showingNowPlaying || navigator.artViewer != nil) {
            resignWindowFocus()
        }
    }

    var body: some View {
        @Bindable var navigator = navigator
        splitView
        // The window's Light or Dark (Mac only), on the split view as it always was.
        .windowAppearance()
        // Same page, different colours: Plain toggled, or plays changed an artist's featured album.
        .onChange(of: coverColours) { navigator.coverTint.refresh() }
        .onChange(of: history.version) { navigator.coverTint.refresh() }
        .overlay { stateOverlay }
        .overlay { HeroOverlay() }
        .overlay { NowPlayingOverlay() }
        .overlay { ArtViewerOverlay() }
        .modifier(PlaybackAccent())
        // These full-window views cover the toolbar's area, so its items would only float over them.
        .windowToolbar(navigator.showingNowPlaying || navigator.artViewer != nil ? .hidden : .automatic)
        .sheet(item: $navigator.editing) { FilterEditorSheet(draft: $0) }
        .sheet(item: $navigator.renamingElement) { ref in
            NameSheet(title: "Element Name", symbol: "rectangle.grid.1x2",
                      name: pages.element(ref.elementID, on: ref.pageID)?.filter.name ?? "") {
                pages.renameElement(ref.elementID, on: ref.pageID, to: $0)
            }
        }
        .task {
            await library.load()
            library.startWatching()
        }
        .onAppear { selectFirstPageIfNeeded() }
        .onChange(of: pages.tree) { selectFirstPageIfNeeded() }
        .onChange(of: hiddenLibraryPages) { selectFirstPageIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            Task { await library.reloadIfMusicChanged() }
        }
    }

    @ViewBuilder
    private var detail: some View {
        let snapshot = library.snapshot
        switch selection {
        case .page(let id):
            PageView(pageID: id)
        case nil:
            ContentUnavailableView {
                Label("No Pages", systemImage: "rectangle.grid.1x2")
            } actions: {
                Button("New Page") { navigator.create(folder: false, in: pages) }
                    .beatGlassButtonStyle(prominent: true)
            }
        case .albums:
            AlbumsLibraryView()
        case .artists:
            ArtistGridView(title: "Artists", artists: snapshot.artists, memory: .artists)
        case .genres:
            GenreGridView(title: "Genres", genres: snapshot.genres, memory: .genres)
        case .songs:
            AlbumSongsView(title: "Songs", tracks: snapshot.tracks)
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .album(let id): AlbumDetailView(albumID: id)
        case .artist(let id): ArtistDetailView(artistID: id)
        case .genre(let id): GenreDetailView(genreID: id)
        case .element(let element): ElementDetailView(route: element)
        }
    }

    /// At launch, restores the page saved at the last quit. Falls back to the first page when nothing is
    /// selected, the selected page was deleted, or the selected Library page was hidden in Settings.
    private func selectFirstPageIfNeeded() {
        switch selection {
        case .page(let id) where pages.node(id) != nil: return
        case nil where navigator.restoreSavedSelection(tree: pages.tree, hidden: LibraryPage.hidden(in: hiddenLibraryPages)):
            return
        case .page, nil: navigator.selection = pages.tree.firstPageID.map(SidebarItem.page)
        default:
            guard let libraryPage = LibraryPage(selection),
                  LibraryPage.hidden(in: hiddenLibraryPages).contains(libraryPage) else { return }
            navigator.selection = pages.tree.firstPageID.map(SidebarItem.page)
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        switch library.state {
        case .loading:
            ProgressView("Reading your Music library…")
                .padding(24)
                .beatGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        case .failed(let message):
            ContentUnavailableView {
                Label("No Access to Music Library", systemImage: "lock")
            } description: {
                Text(message)
            } actions: {
                Button("Open Privacy Settings") { openPrivacySettings() }
                .beatGlassButtonStyle(prominent: true)
                Button("Try Again") { Task { await library.load() } }
                    .beatGlassButtonStyle()
            }
            .background(.background)
        case .loaded where library.snapshot.tracks.isEmpty:
            // Over the page, not blocking it: Settings and the sidebar stay usable.
            ContentUnavailableView("No Music Yet", systemImage: "music.note", description: Text(emptyLibraryHint))
                .frame(maxWidth: 440, maxHeight: 260)
                .beatGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .allowsHitTesting(false)
                // On a phone the page fills the screen: keep the card at the bottom, off its rows.
                .frame(maxHeight: .infinity, alignment: compact ? .bottom : .center)
                .padding(.horizontal, compact ? 16 : 0)
                .padding(.bottom, compact ? 24 : 0)
        case .idle, .loaded:
            EmptyView()
        }
    }
}

/// Sets `\.playbackAccent` for the whole window from the playing song's cover. Only views that read it redraw
/// when the song changes.
private struct PlaybackAccent: ViewModifier {
    @Environment(PlaybackQueue.self) private var queue
    @Environment(ArtworkCache.self) private var artwork
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appearance.coverColours") private var coverColours = true
    @State private var palette: ArtworkPalette?

    private var source: ArtworkSource? { queue.current.map { ArtworkSource($0) } }

    func body(content: Content) -> some View {
        content
            .environment(\.playbackAccent, accent)
            .task(id: source) {
                guard let source else { palette = nil; return }
                palette = artwork.cachedPalette(source)
                if palette == nil { palette = await artwork.palette(source) }
            }
    }

    private var accent: Color {
        guard coverColours, let rgb = BarTint.color(for: palette) else { return .accentColor }
        return BarTint.readable(rgb, dark: colorScheme == .dark).color
    }
}
