import SwiftUI

/// Which albums Library ▸ Albums shows, picked from its artist list.
enum AlbumArtistFilter: Hashable {
    case all
    case compilations
    /// An album artist, by `Artist.id`.
    case artist(String)
}

/// Library ▸ Albums: the album grid with a list of album artists beside it to narrow it down. Picking an
/// artist here only filters; it doesn't open the artist's page.
struct AlbumsLibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigator.self) private var navigator
    @AppStorage("albums.artistList") private var showsList = true
    @State private var width: CGFloat = 1000

    /// Below this the grid needs the room more than the list does.
    private static let listMinimumWindowWidth: CGFloat = 700

    var body: some View {
        let snapshot = library.snapshot
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
    }

    /// Narrowed by the grid's search too: only artists with a matching album, counting just those albums.
    private func artistList(_ snapshot: LibrarySnapshot) -> some View {
        let search = navigator.search(.albums, else: .constant("")).wrappedValue
        let matching = snapshot.albums(snapshot.albums, matching: search)
        let matchingIDs = SearchText.words(search).isEmpty ? nil : Set(matching.map(\.id))
        let artists: [(artist: Artist, count: Int)] = snapshot.artists.compactMap { artist in
            let count = matchingIDs.map { ids in artist.albumIDs.count { ids.contains($0) } } ?? artist.albumIDs.count
            return count > 0 ? (artist, count) : nil
        }
        let compilations = matching.count { $0.isCompilation }
        return List(selection: Binding(
            get: { navigator.albumArtistFilter },
            set: { navigator.albumArtistFilter = $0 ?? .all }
        )) {
            row("All Artists", count: matching.count).tag(AlbumArtistFilter.all)
            if compilations > 0 {
                row("Compilations", count: compilations).tag(AlbumArtistFilter.compilations)
            }
            Section("Artists") {
                ForEach(artists, id: \.artist.id) { item in
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
