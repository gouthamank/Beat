import Foundation

/// One thing Quick Open can find, and where picking it goes.
struct QuickOpenItem: Identifiable, Hashable, Sendable {
    /// Also the order groups are listed in when their best matches are equally good.
    enum Kind: Int, CaseIterable, Comparable, Sendable {
        case page, album, artist, genre, song

        var title: String {
            switch self {
            case .page: "Pages"
            case .album: "Albums"
            case .artist: "Artists"
            case .genre: "Genres"
            case .song: "Songs"
            }
        }

        static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
    }

    enum Target: Hashable, Sendable {
        /// A sidebar page or Library page, selected.
        case sidebar(SidebarItem)
        case album(PersistentID)
        case artist(String)
        case genre(String)
        /// Its album opens with the song highlighted.
        case song(PersistentID, album: PersistentID)
    }

    let target: Target
    let kind: Kind
    let title: String
    let subtitle: String
    /// Pages and Library pages show their sidebar symbol; the rest show art.
    var symbol: String?

    var id: Target { target }
}

/// Quick Open's results: one group per kind, best first.
struct QuickOpenGroup: Identifiable, Equatable, Sendable {
    let kind: QuickOpenItem.Kind
    let items: [QuickOpenItem]

    var id: QuickOpenItem.Kind { kind }
}

/// Everything Quick Open searches, folded once per library or sidebar change so a keystroke only compares text.
/// Pure: built and searched off the main actor by `QuickOpenModel`.
struct QuickOpenIndex: Sendable {
    private struct Entry: Sendable {
        let item: QuickOpenItem
        /// Everything a search may match (a song's artist and album, an album's artists…).
        let text: String
        /// The item's own name, for ranking.
        let name: String
    }

    /// How many of each kind are shown. Songs get a few more: there are far more of them.
    static let limits: [QuickOpenItem.Kind: Int] = [.page: 5, .album: 5, .artist: 5, .genre: 5, .song: 8]

    private var entries: [QuickOpenItem.Kind: [Entry]] = [:]

    static let empty = QuickOpenIndex()

    private init() {}

    init(snapshot: LibrarySnapshot, tree: PageTree, libraryPages: [LibraryPage]) {
        // Pages only: picking a folder only opened it in the sidebar. A page is also found by its folders' names.
        var pages: [Entry] = []
        func walk(_ nodes: [SidebarNode], _ folders: [String]) {
            for node in nodes {
                if let children = node.children {
                    walk(children, folders + [node.name])
                    continue
                }
                let folderPath = folders.joined(separator: " ▸ ")
                let item = QuickOpenItem(target: .sidebar(.page(node.id)), kind: .page, title: node.name,
                                         subtitle: folderPath.isEmpty ? "Page" : folderPath, symbol: node.symbol)
                let name = SearchText.fold(node.name)
                pages.append(Entry(item: item, text: SearchText.fold((folders + [node.name]).joined(separator: " ")), name: name))
            }
        }
        walk(tree.nodes, [])
        for page in libraryPages {
            let item = QuickOpenItem(target: .sidebar(page.item), kind: .page, title: page.title, subtitle: "Library",
                                     symbol: page.symbol)
            let name = SearchText.fold(page.title)
            pages.append(Entry(item: item, text: name, name: name))
        }
        entries[.page] = pages

        entries[.album] = snapshot.albums.map { album in
            let item = QuickOpenItem(target: .album(album.id), kind: .album, title: album.title, subtitle: album.artist)
            return Entry(item: item, text: snapshot.albumSearchText[album.id] ?? SearchText.fold("\(album.title) \(album.artist)"),
                         name: SearchText.fold(album.title))
        }
        entries[.artist] = snapshot.artists.map { artist in
            let item = QuickOpenItem(target: .artist(artist.id), kind: .artist, title: artist.name,
                                     subtitle: artist.albumIDs.count.counted("album"))
            let name = SearchText.fold(artist.name)
            return Entry(item: item, text: name, name: name)
        }
        entries[.genre] = snapshot.genres.map { genre in
            let item = QuickOpenItem(target: .genre(genre.id), kind: .genre, title: genre.name,
                                     subtitle: genre.trackCount.counted("song"))
            let name = SearchText.fold(genre.name)
            return Entry(item: item, text: name, name: name)
        }
        entries[.song] = snapshot.tracks.map { track in
            let subtitle = [track.displayArtist, track.album].filter { !$0.isEmpty }.joined(separator: " · ")
            let item = QuickOpenItem(target: .song(track.id, album: track.albumID), kind: .song, title: track.title,
                                     subtitle: subtitle)
            return Entry(item: item, text: snapshot.trackSearchText[track.id] ?? SongsQuery.searchText(track),
                         name: SearchText.fold(track.title))
        }
    }

    /// The matches for `query`: every word must appear in an item's text. Within a kind, names that are the query,
    /// then names starting with it, then names where every word starts a word, then names containing every word, then
    /// matches on other text (a song found by its artist); shorter names first, then library order. Groups are
    /// ordered by their best match, then by kind.
    func results(for query: String) -> [QuickOpenGroup] {
        let words = SearchText.words(query)
        guard !words.isEmpty else { return [] }
        let phrase = words.joined(separator: " ")
        var groups: [(group: QuickOpenGroup, best: Int)] = []
        for kind in QuickOpenItem.Kind.allCases {
            var matches: [(rank: Int, length: Int, order: Int, item: QuickOpenItem)] = []
            for (order, entry) in (entries[kind] ?? []).enumerated() where SearchText.matches(entry.text, words) {
                matches.append((Self.rank(entry.name, phrase: phrase, words: words), entry.name.count, order, entry.item))
            }
            guard !matches.isEmpty else { continue }
            matches.sort { ($0.rank, $0.length, $0.order) < ($1.rank, $1.length, $1.order) }
            let shown = matches.prefix(Self.limits[kind] ?? 5)
            groups.append((QuickOpenGroup(kind: kind, items: shown.map(\.item)), shown[shown.startIndex].rank))
        }
        return groups.sorted { ($0.best, $0.group.kind) < ($1.best, $1.group.kind) }.map(\.group)
    }

    /// 0 best. `name`, `phrase` and `words` are already folded.
    static func rank(_ name: String, phrase: String, words: [String]) -> Int {
        if name == phrase { return 0 }
        if name.hasPrefix(phrase) { return 1 }
        if words.allSatisfy({ startsWord($0, in: name) }) { return 2 }
        if SearchText.matches(name, words) { return 3 }
        return 4
    }

    /// Whether `word` appears in `text` at the start of a word: at the very start, or after a space or punctuation.
    static func startsWord(_ word: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let found = text.range(of: word, range: searchStart..<text.endIndex) {
            if found.lowerBound == text.startIndex { return true }
            let before = text[text.index(before: found.lowerBound)]
            if !before.isLetter && !before.isNumber { return true }
            searchStart = text.index(after: found.lowerBound)
        }
        return false
    }
}

/// What Return does on a song in Quick Open (Settings ▸ General ▸ Quick Open).
enum QuickOpenSongAction: String, CaseIterable, Sendable {
    case album, songs, play

    static let key = "quickOpen.song"

    var title: String {
        switch self {
        case .album: "Open Its Album"
        case .songs: "Show in Songs"
        case .play: "Play"
        }
    }
}

/// What Return does on an album in Quick Open.
enum QuickOpenAlbumAction: String, CaseIterable, Sendable {
    case open, play

    static let key = "quickOpen.album"

    var title: String {
        switch self {
        case .open: "Open"
        case .play: "Play"
        }
    }
}

/// What picking a Quick Open result does. Pure, so the settings and ⌥Return are tested without the panel.
enum QuickOpenAction: Equatable, Sendable {
    case select(SidebarItem)
    /// Opened on the Library page that lists it (`AppNavigator.goTo`).
    case go(Route, in: LibraryPage, highlighting: PersistentID?)
    /// Library ▸ Songs, scrolled to the song and highlighted.
    case showInSongs(PersistentID, album: PersistentID)
    /// The album from its start, or from a song on through the rest of the album.
    case playAlbum(PersistentID, from: PersistentID?)

    /// `alternate` is ⌥Return: the other of opening and playing. A song set to play opens its album on ⌥Return.
    static func resolve(_ target: QuickOpenItem.Target, song: QuickOpenSongAction, album: QuickOpenAlbumAction,
                        alternate: Bool) -> QuickOpenAction {
        switch target {
        case .sidebar(let item):
            return .select(item)
        case .artist(let id):
            return .go(.artist(id), in: .artists, highlighting: nil)
        case .genre(let id):
            return .go(.genre(id), in: .genres, highlighting: nil)
        case .album(let id):
            return (album == .play) != alternate ? .playAlbum(id, from: nil) : .go(.album(id), in: .albums, highlighting: nil)
        case .song(let id, let albumID):
            if (song == .play) != alternate { return .playAlbum(albumID, from: id) }
            return song == .songs ? .showInSongs(id, album: albumID) : .go(.album(albumID), in: .albums, highlighting: id)
        }
    }
}
