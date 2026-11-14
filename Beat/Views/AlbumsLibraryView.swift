import SwiftUI

/// Which albums Library ▸ Albums shows, picked from its artist list.
enum AlbumArtistFilter: Hashable {
    case all
    case compilations
    /// An album artist, by `Artist.id`.
    case artist(String)
}

/// Library ▸ Albums: the album grid, narrowed by album artist. Picking an artist here only filters; it doesn't open
/// the artist's page. On the Mac the artists are a list beside the grid; on iPad and iPhone a menu in the toolbar,
/// since a list inside the page sat under the navigation bar's title and search and the window's now-playing bar,
/// which span the whole page column.
struct AlbumsLibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigator.self) private var navigator
    #if os(macOS)
    @AppStorage("albums.artistList") private var showsList = true
    @State private var width: CGFloat = 1000

    /// Below this the grid needs the room more than the list does.
    private static let listMinimumWindowWidth: CGFloat = 700
    #endif

    var body: some View {
        let snapshot = library.snapshot
        #if os(macOS)
        HStack(spacing: 0) {
            if showsList, width >= Self.listMinimumWindowWidth {
                HStack(spacing: 0) {
                    artistList(snapshot)
                        .frame(width: 210)
                    Divider()
                }
                // Slides in from the page's leading edge like the sidebar, while the grid narrows beside it.
                .transition(.move(edge: .leading))
            }
            AlbumGridView(title: title(snapshot), albums: albums(snapshot), memory: .albums)
        }
        // Keeps the sliding list from drawing over the sidebar. A mask reaching into the safe areas, not
        // `.clipped()`, so the grid still scrolls under the toolbar.
        .mask { Rectangle().ignoresSafeArea() }
        // Keyed on the value rather than `$showsList.animation(_:)`: an `@AppStorage` write reaches the view
        // without the toggle's animation.
        .animation(.smooth(duration: 0.3), value: showsList)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: navigator.albumArtistFilter) { navigator.requestScrollToTop(.albums) }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Toggle(isOn: $showsList) { Label("Artists", systemImage: "sidebar.squares.left") }
                    .help(showsList ? "Hide Artist List" : "Show Artist List")
            }
        }
        #else
        AlbumGridView(title: title(snapshot), albums: albums(snapshot), memory: .albums)
            .onChange(of: navigator.albumArtistFilter) { navigator.requestScrollToTop(.albums) }
            .toolbar {
                ToolbarItem(placement: .navigation) { artistMenu(snapshot) }
            }
        #endif
    }

    /// The artists to pick from, narrowed by the grid's search too: only artists with a matching album, counting
    /// just those albums.
    private func choices(_ snapshot: LibrarySnapshot) -> (all: Int, compilations: Int, artists: [(artist: Artist, count: Int)]) {
        let search = navigator.search(.albums, else: .constant("")).wrappedValue
        let matching = snapshot.albums(snapshot.albums, matching: search)
        let matchingIDs = SearchText.words(search).isEmpty ? nil : Set(matching.map(\.id))
        let artists: [(artist: Artist, count: Int)] = snapshot.artists.compactMap { artist in
            let count = matchingIDs.map { ids in artist.albumIDs.count { ids.contains($0) } } ?? artist.albumIDs.count
            return count > 0 ? (artist, count) : nil
        }
        return (matching.count, matching.count { $0.isCompilation }, artists)
    }

    #if os(macOS)
    private var selection: Binding<AlbumArtistFilter?> {
        Binding(get: { navigator.albumArtistFilter }, set: { navigator.albumArtistFilter = $0 ?? .all })
    }

    private func artistList(_ snapshot: LibrarySnapshot) -> some View {
        let choices = choices(snapshot)
        return List(selection: selection) {
            row("All Artists", count: choices.all).tag(AlbumArtistFilter.all)
            if choices.compilations > 0 {
                row("Compilations", count: choices.compilations).tag(AlbumArtistFilter.compilations)
            }
            Section("Artists") {
                ForEach(choices.artists, id: \.artist.id) { item in
                    row(item.artist.name, count: item.count).tag(AlbumArtistFilter.artist(item.artist.id))
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func row(_ name: String, count: Int) -> some View {
        HStack {
            Text(name).lineLimit(1)
            Spacer(minLength: 4)
            Text("\(count)").font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    #else
    /// The same choices as the Mac's list, as a menu. Its icon fills while an artist is picked (the title names them).
    private func artistMenu(_ snapshot: LibrarySnapshot) -> some View {
        let choices = choices(snapshot)
        return Menu {
            Picker("Artist", selection: Binding(get: { navigator.albumArtistFilter }, set: { navigator.albumArtistFilter = $0 })) {
                Text("All Artists").tag(AlbumArtistFilter.all)
                if choices.compilations > 0 {
                    Text("Compilations").tag(AlbumArtistFilter.compilations)
                }
                Section("Artists") {
                    ForEach(choices.artists, id: \.artist.id) { item in
                        Text(item.artist.name).tag(AlbumArtistFilter.artist(item.artist.id))
                    }
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Artists", systemImage: navigator.albumArtistFilter == .all
                  ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityIdentifier("albums.artistMenu")
    }
    #endif

    private func albums(_ snapshot: LibrarySnapshot) -> [Album] {
        switch navigator.albumArtistFilter {
        case .all: snapshot.albums
        case .compilations: snapshot.albums.filter(\.isCompilation)
        case .artist(let id): snapshot.artistsByID[id]?.albumIDs.compactMap { snapshot.albumsByID[$0] } ?? []
        }
    }

    private func title(_ snapshot: LibrarySnapshot) -> String {
        switch navigator.albumArtistFilter {
        case .all: "Albums"
        case .compilations: "Compilations"
        case .artist(let id): snapshot.artistsByID[id]?.name ?? "Albums"
        }
    }
}
