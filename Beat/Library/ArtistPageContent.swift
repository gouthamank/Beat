import Foundation

/// Everything the artist page shows, worked out from the library in one pass (off the main actor).
struct ArtistPageContent: Equatable, Sendable {
    /// Top songs by plays (Music's count plus Beat's), most played first.
    var topSongs: [Track] = []
    /// Full-length albums, in the Albums section's sort order.
    var albums: [Album] = []
    /// Short releases (see `isShortRelease`), in their section's sort order.
    var singlesAndEPs: [Album] = []
    /// Other album artists' albums (compilations included) with a track credited to this artist.
    var appearsOn: [Album] = []
    var songCount = 0
    var duration: TimeInterval = 0
    var plays = 0
    /// The album the page takes its colours from: the most played, else the newest.
    var featuredAlbumID: PersistentID?

    static let topSongLimit = 10

    /// Up to six tracks and under half an hour: a single or an EP rather than an album.
    static func isShortRelease(_ album: Album) -> Bool {
        album.trackIDs.count <= 6 && album.duration < 30 * 60
    }

    /// The album an artist page takes its colours from: the most played (Music's plays plus Beat's), else
    /// the newest. Shared by the page and `CoverTint`, so the page and the sidebar always agree.
    static func featuredAlbumID(artist: Artist, snapshot: LibrarySnapshot, history: [PersistentID: PlayHistoryStore.Stats]) -> PersistentID? {
        let own = artist.albumIDs.compactMap { snapshot.albumsByID[$0] }
        var best: (id: PersistentID, plays: Int)?
        for album in own {
            let plays = snapshot.tracks(of: album).reduce(0) { $0 + $1.playCount + (history[$1.id]?.playCount ?? 0) }
            guard plays > 0 else { continue }
            if best == nil || plays > best!.plays || (plays == best!.plays && album.id < best!.id) { best = (album.id, plays) }
        }
        if let best { return best.id }
        // Newest: the latest year, and within it the first in library order.
        return own.enumerated().max { ($0.element.year, $1.offset) < ($1.element.year, $0.offset) }?.element.id
    }

    /// Everything from the artist's own albums: quick (a few hundred tracks at most), so the page builds it
    /// as it appears and shows it in the first frame. `appearsOn` is left empty; see `appearsOn(artist:…)`.
    static func local(artist: Artist, snapshot: LibrarySnapshot, history: [PersistentID: PlayHistoryStore.Stats],
                      sorts: ArtistSorts = ArtistSorts()) -> ArtistPageContent {
        func plays(_ track: Track) -> Int { track.playCount + (history[track.id]?.playCount ?? 0) }

        var content = ArtistPageContent()
        let own = artist.albumIDs.compactMap { snapshot.albumsByID[$0] }
        let tracks = own.flatMap(snapshot.tracks(of:))
        content.songCount = tracks.count
        content.duration = tracks.reduce(0) { $0 + $1.duration }
        content.plays = tracks.reduce(0) { $0 + plays($1) }
        content.topSongs = Array(tracks.filter { plays($0) > 0 }
            .sorted { (plays($0), $1.title) > (plays($1), $0.title) }
            .prefix(topSongLimit))
        content.featuredAlbumID = featuredAlbumID(artist: artist, snapshot: snapshot, history: history)

        // Each section in its own chosen order, aggregated the way a smart filter would.
        let library = PreparedLibrary(snapshot: snapshot, tracks: tracks, history: history)
        content.albums = SmartFilterEngine.sort(own.filter { !isShortRelease($0) }, by: sorts.albums, in: library)
        content.singlesAndEPs = SmartFilterEngine.sort(own.filter(isShortRelease), by: sorts.singlesAndEPs, in: library)
        return content
    }

    /// Other album artists' albums (compilations included) crediting the artist, in that section's order.
    /// Scans the whole library, so the page runs it off the main actor.
    static func appearsOn(artist: Artist, snapshot: LibrarySnapshot, history: [PersistentID: PlayHistoryStore.Stats],
                          sort: SortKey) -> [Album] {
        let ownIDs = Set(artist.albumIDs)
        var seen = Set<PersistentID>()
        var albums: [Album] = []
        var tracks: [Track] = []
        for track in snapshot.tracks where !ownIDs.contains(track.albumID) && !seen.contains(track.albumID) {
            if ArtistCredits.matches(trackArtist: track.artist, name: artist.name), let album = snapshot.albumsByID[track.albumID] {
                seen.insert(album.id)
                albums.append(album)
                tracks.append(contentsOf: snapshot.tracks(of: album))
            }
        }
        let library = PreparedLibrary(snapshot: snapshot, tracks: tracks, history: history)
        return SmartFilterEngine.sort(albums, by: sort, in: library)
    }

    /// Both together, for tests and anywhere the page's full content is wanted at once.
    static func build(artist: Artist, snapshot: LibrarySnapshot, history: [PersistentID: PlayHistoryStore.Stats],
                      sorts: ArtistSorts = ArtistSorts()) -> ArtistPageContent {
        var content = local(artist: artist, snapshot: snapshot, history: history, sorts: sorts)
        content.appearsOn = appearsOn(artist: artist, snapshot: snapshot, history: history, sort: sorts.appearsOn)
        return content
    }
}

/// The sort order of each album section on artist pages: one setting for every artist (how you like to
/// browse isn't about a particular artist), separate per section. Saved as JSON; custom fields travel
/// inside their keys, as in smart filters.
struct ArtistSorts: Codable, Equatable, Sendable {
    enum Section: CaseIterable, Sendable { case albums, singlesAndEPs, appearsOn }

    static let storageKey = "artist.sorts"
    static let newestFirst = SortKey(field: .field(.year), ascending: false)
    /// The built-in fields offered for albums, before custom fields and Random.
    static let fields: [Field] = [.year, .album, .dateAdded, .playCount, .lastPlayed, .rating, .duration]

    var albums = newestFirst
    var singlesAndEPs = newestFirst
    var appearsOn = newestFirst

    subscript(section: Section) -> SortKey {
        get {
            switch section {
            case .albums: albums
            case .singlesAndEPs: singlesAndEPs
            case .appearsOn: appearsOn
            }
        }
        set {
            switch section {
            case .albums: albums = newValue
            case .singlesAndEPs: singlesAndEPs = newValue
            case .appearsOn: appearsOn = newValue
            }
        }
    }

    /// Saved sorts with custom fields brought up to date, or newest first when nothing (readable) is saved.
    static func decode(_ data: Data?, customFields: [CustomField]) -> ArtistSorts {
        guard let data, var sorts = try? JSONDecoder().decode(ArtistSorts.self, from: data) else { return ArtistSorts() }
        for section in Section.allCases { sorts[section] = sorts[section].refreshed(customFields) }
        return sorts
    }

    func encoded() -> Data? { try? JSONEncoder().encode(self) }

    /// A new field starts A to Z for text and highest/newest first otherwise.
    static func key(for field: SortField) -> SortKey {
        if case .field(let f) = field, f.type == .text { return SortKey(field: field, ascending: true) }
        if case .custom = field { return SortKey(field: field, ascending: true) }
        return SortKey(field: field, ascending: false)
    }

    static func title(_ field: SortField) -> String {
        switch field {
        case .field(.album): "Title"
        case .field(.playCount): "Plays"
        case .field(.duration): "Length"
        case .field(let f): f.title
        case .custom(let custom): custom.name
        case .random: "Random"
        }
    }
}

/// Whether a track's artist credit names an artist, as a whole name: "A feat. B", "A & B", "A x B",
/// "A, B" and "A vs B" all credit B; "Anna" doesn't credit "Ann".
enum ArtistCredits {
    private static let separators = [" featuring ", " feat. ", " feat ", " ft. ", " ft ", " vs. ", " vs ",
                                     " & ", " and ", " x ", " + ", ", ", " with "]

    static func names(in credit: String) -> [String] {
        var parts = [SearchText.fold(credit)]
        for separator in separators {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func matches(trackArtist: String, name: String) -> Bool {
        let target = SearchText.fold(name).trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return false }
        return names(in: trackArtist).contains(target)
    }
}
