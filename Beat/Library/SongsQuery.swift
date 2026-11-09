import Foundation

/// Search matching shared by the Songs table and album search: every typed word must appear,
/// ignoring case and diacritics.
enum SearchText {
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    static func words(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    static func matches(_ folded: String, _ words: [String]) -> Bool {
        words.allSatisfy { folded.contains($0) }
    }
}

/// A Songs table column, also its sort key.
enum SongColumn: Hashable, Sendable {
    case title, artist, album, albumArtist, time, trackNumber, discNumber, genre, year
    case plays, skips, rating, bpm, bitRate, sampleRate, kind, composer, grouping, comments
    case dateAdded, lastPlayed, dateModified
    case custom(UUID)
}

/// The Table's sort descriptor. Custom-field columns need precomputed values, so the real sorting
/// happens in `SongsQuery.apply`; this comparator covers the built-in columns.
struct TrackSort: SortComparator, Hashable {
    var column: SongColumn
    var order: SortOrder = .forward

    func compare(_ a: Track, _ b: Track) -> ComparisonResult {
        SongsQuery.compare(a, b, by: self, customValues: [:])
    }
}

/// Filters and sorts songs. Pure, and run off the main actor by `SongsModel`.
enum SongsQuery {
    private enum Value {
        case text(String?)
        case number(Double?)
    }

    static func apply(_ tracks: [Track], search: String, sort: [TrackSort],
                      customValues: [UUID: [PersistentID: String]]) -> [Track] {
        let words = SearchText.words(search)
        let filtered = words.isEmpty ? tracks : tracks.filter { t in
            SearchText.matches(SearchText.fold("\(t.title) \(t.artist) \(t.albumArtist) \(t.album)"), words)
        }
        guard !sort.isEmpty else { return filtered }
        // Index as the last tie-breaker keeps equal rows in library order.
        return filtered.enumerated().sorted { x, y in
            for key in sort {
                let r = compare(x.element, y.element, by: key, customValues: customValues)
                if r != .orderedSame { return r == .orderedAscending }
            }
            return x.offset < y.offset
        }.map(\.element)
    }

    /// Missing values (empty text, no date, no custom match) sort last in either direction.
    static func compare(_ a: Track, _ b: Track, by key: TrackSort, customValues: [UUID: [PersistentID: String]]) -> ComparisonResult {
        let ascending = key.order == .forward
        switch (value(a, key.column, customValues), value(b, key.column, customValues)) {
        case (.text(let x), .text(let y)):
            switch (x, y) {
            case (nil, nil): return .orderedSame
            case (nil, _): return .orderedDescending
            case (_, nil): return .orderedAscending
            case (let x?, let y?):
                let r = x.localizedStandardCompare(y)
                if r == .orderedSame { return r }
                return (r == .orderedAscending) == ascending ? .orderedAscending : .orderedDescending
            }
        case (.number(let x), .number(let y)):
            switch (x, y) {
            case (nil, nil): return .orderedSame
            case (nil, _): return .orderedDescending
            case (_, nil): return .orderedAscending
            case (let x?, let y?):
                if x == y { return .orderedSame }
                return (x < y) == ascending ? .orderedAscending : .orderedDescending
            }
        default:
            return .orderedSame
        }
    }

    private static func value(_ t: Track, _ column: SongColumn, _ custom: [UUID: [PersistentID: String]]) -> Value {
        func text(_ s: String) -> Value { .text(s.isEmpty ? nil : s) }
        func number(_ n: Int) -> Value { .number(Double(n)) }
        func date(_ d: Date?) -> Value { .number(d?.timeIntervalSinceReferenceDate) }
        switch column {
        case .title: return text(t.title)
        case .artist: return text(t.displayArtist)
        case .album: return text(t.album)
        case .albumArtist: return text(t.albumArtist)
        case .genre: return text(t.genre)
        case .kind: return text(t.kind)
        case .composer: return text(t.composer)
        case .grouping: return text(t.grouping)
        case .comments: return text(t.comments)
        case .time: return .number(t.duration)
        case .trackNumber: return number(t.trackNumber)
        case .discNumber: return number(t.discNumber)
        case .year: return t.year > 0 ? number(t.year) : .number(nil)
        case .plays: return number(t.playCount)
        case .skips: return number(t.skipCount)
        case .rating: return number(t.stars)
        case .bpm: return t.bpm > 0 ? number(t.bpm) : .number(nil)
        case .bitRate: return number(t.bitrate)
        case .sampleRate: return number(t.sampleRate)
        case .dateAdded: return date(t.dateAdded)
        case .lastPlayed: return date(t.lastPlayed)
        case .dateModified: return date(t.dateModified)
        case .custom(let id): return .text(custom[id]?[t.id])
        }
    }

    /// Each custom field's value for every track, compiling each pattern once.
    static func customValues(_ fields: [CustomField], for tracks: [Track]) -> [UUID: [PersistentID: String]] {
        var values: [UUID: [PersistentID: String]] = [:]
        for field in fields {
            let extract = field.extractor()
            var byTrack: [PersistentID: String] = [:]
            for track in tracks {
                if let value = extract(track) { byTrack[track.id] = value }
            }
            values[field.id] = byTrack
        }
        return values
    }
}

/// One album's matching songs, for the Album by Artist view.
struct SongGroup: Identifiable, Sendable {
    let album: Album
    let tracks: [Track]

    var id: PersistentID { album.id }
}

extension SongsQuery {
    /// Groups songs by album in library album order (artist, year, title), tracks in disc/track order.
    /// Songs whose album isn't in `albums` are left out.
    static func groupByAlbum(_ tracks: [Track], albums: [Album]) -> [SongGroup] {
        let byAlbum = Dictionary(grouping: tracks, by: \.albumID)
        return albums.compactMap { album in
            guard let members = byAlbum[album.id] else { return nil }
            let ordered = members.sorted {
                ($0.discNumber, $0.trackNumber, $0.title) < ($1.discNumber, $1.trackNumber, $1.title)
            }
            return SongGroup(album: album, tracks: ordered)
        }
    }
}

/// One album artist's albums, for the pinned artist headers in Album by Artist.
struct ArtistSection: Identifiable, Sendable {
    let name: String
    let groups: [SongGroup]

    /// The album artist's key, matching `Artist.id` (case-folded name).
    var id: String { name.lowercased() }
    var songCount: Int { groups.reduce(0) { $0 + $1.tracks.count } }
}

extension SongsQuery {
    /// Splits album groups (already in artist order) into runs that share an album artist.
    static func sectionsByArtist(_ groups: [SongGroup]) -> [ArtistSection] {
        var sections: [ArtistSection] = []
        var current: [SongGroup] = []
        for group in groups {
            if let last = current.last, last.album.artist.lowercased() != group.album.artist.lowercased() {
                sections.append(ArtistSection(name: current[0].album.artist, groups: current))
                current = []
            }
            current.append(group)
        }
        if let first = current.first { sections.append(ArtistSection(name: first.album.artist, groups: current)) }
        return sections
    }
}
