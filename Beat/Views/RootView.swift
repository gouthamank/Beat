import AppKit
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
    /// The system's Light or Dark (System Settings ▸ Appearance), kept current while Beat runs.
    @State private var systemScheme = RootView.currentSystemScheme()

    private static let systemAppearanceChanged = Notification.Name("AppleInterfaceThemeChangedNotification")

    /// Read from the global preference rather than the window, which may be showing a cover's scheme.
    private static func currentSystemScheme() -> ColorScheme {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark" ? .dark : .light
    }
    @Environment(PlayHistoryStore.self) private var history

    private var selection: SidebarItem? { navigator.selection }

    private var windowScheme: ColorScheme {
        navigator.coverTint.current.map { $0.palette.isDark ? .dark : .light } ?? systemScheme
    }

    /// Back from a cover page, a grid's toolbar search field redrew its bezel in the window's Light or Dark
    /// but kept its text in the page's: black text on a dark field. Setting the text again redraws it in
    /// the window's current colours.
    private static func resetToolbarSearchFields() {
        func reset(_ view: NSView) {
            if let field = view as? NSSearchField {
                field.appearance = nil
                field.textColor = .controlTextColor
                field.stringValue = field.stringValue
                (field.currentEditor() as? NSTextView)?.textColor = .controlTextColor
                field.needsDisplay = true
            }
            view.subviews.forEach(reset)
        }
        for window in NSApp.windows {
            if let frame = window.contentView?.superview { reset(frame) }
        }
    }


    /// The narrowest the page column gets, on every page (root or pushed).
    static let detailMinWidth: CGFloat = 680

    /// The sidebar, the page column and the window's now-playing bar. Split out of `body`, which grew too
    /// long for the compiler to type-check in reasonable time.
    private var splitView: some View {
        @Bindable var navigator = navigator
        return NavigationSplitView {
            SidebarView(selection: $navigator.selection)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } detail: {
            NavigationStack(path: navigator.pathBinding(for: selection)) {
                detail
                    .nowPlayingBarSpace()
                    .navigationDestination(for: Route.self) { route in
                        // Pushed pages are hosted separately and set the window's minimum themselves: without
                        // their own, an album page let the window shrink below the page underneath, which
                        // then overflowed the column and shifted everything sideways.
                        // Opaque, toolbar included: after an album page was pushed over a genre or See All grid and
                        // popped, the page underneath showed through the grid, which draws no background itself.
                        destination(route).nowPlayingBarSpace().frame(minWidth: Self.detailMinWidth)
                            .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
                    }
            }
            .id(selection)
            // Where the window's now-playing bar goes (see WindowNowPlayingBar).
            .background { DetailColumnReader(navigator: navigator) }
            // The window's minimum width lives here, not on the window's root view: a root `minWidth` cut
            // the sidebar's expand animation short (the page slid halfway, then snapped).
            .frame(minWidth: Self.detailMinWidth)
        }
        // One bar for the window, above pushed pages. Before `.disabled`, so it's disabled with the rest of the
        // window behind full-window views, and before the overlays that must draw over it.
        .overlay { WindowNowPlayingBar() }
        // Full-window views cover the window, so Tab (and VoiceOver) must stay inside them rather than
        // reach the sidebar and page underneath.
        .disabled(navigator.showingNowPlaying || navigator.artViewer != nil)
        .accessibilityHidden(navigator.showingNowPlaying || navigator.artViewer != nil)
        .onChange(of: navigator.showingNowPlaying || navigator.artViewer != nil) {
            // Nothing keeps focus across the switch: a control left focused underneath would take Space
            // and the first Tab. Esc and other shortcuts don't need a focused view.
            Task {
                await Task.yield()
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    var body: some View {
        @Bindable var navigator = navigator
        splitView
        // While an album or artist page shows its colours, the whole window (toolbar, divider, sidebar
        // material) takes the cover's lightness. Otherwise the system's own Light or Dark, set explicitly:
        // `preferredColorScheme(nil)` doesn't restore a window that was given a scheme, so after a pale cover
        // the sidebar stayed in Light mode.
        .preferredColorScheme(windowScheme)
        .onChange(of: windowScheme) {
            Task {
                // After the toolbar has rebuilt for the page now in front.
                try? await Task.sleep(for: .milliseconds(50))
                Self.resetToolbarSearchFields()
            }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: Self.systemAppearanceChanged)) { _ in
            systemScheme = Self.currentSystemScheme()
        }
        // Same page, different colours: Plain toggled, or plays changed an artist's featured album.
        .onChange(of: coverColours) { navigator.coverTint.refresh() }
        .onChange(of: history.version) { navigator.coverTint.refresh() }
        .overlay { stateOverlay }
        .overlay { HeroOverlay() }
        .overlay { NowPlayingOverlay() }
        .overlay { ArtViewerOverlay() }
        .modifier(PlaybackAccent())
        // These full-window views cover the toolbar's area, so its items would only float over them.
        .toolbar(navigator.showingNowPlaying || navigator.artViewer != nil ? .hidden : .automatic, for: .windowToolbar)
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
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
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
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media")!)
                }
                .beatGlassButtonStyle(prominent: true)
                Button("Try Again") { Task { await library.load() } }
                    .beatGlassButtonStyle()
            }
            .background(.background)
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
