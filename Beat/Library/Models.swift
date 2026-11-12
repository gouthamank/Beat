import Foundation

typealias PersistentID = UInt64

struct Track: Identifiable, Hashable, Codable, Sendable {
    let id: PersistentID
    var title: String
    var artist: String
    var albumArtist: String
    var album: String
    var albumID: PersistentID
    var composer: String
    var genre: String
    var kind: String
    var comments: String
    var grouping: String
    var year: Int
    /// 0–100, in steps of 20 per star (Music's scale).
    var rating: Int
    var playCount: Int
    var skipCount: Int
    var bpm: Int
    var bitrate: Int
    var sampleRate: Int
    var trackNumber: Int
    var discNumber: Int
    var duration: TimeInterval
    var dateAdded: Date?
    var dateModified: Date?
    var lastPlayed: Date?
    var lastSkipped: Date?
    var isCompilation: Bool
    var hasArtwork: Bool
    var location: URL
    var fileSize: Int64

    var displayArtist: String { artist.isEmpty ? albumArtist : artist }

    /// "MP3 · 320 kbps · 44.1 kHz", "WAV · 1,411 kbps · 48 kHz": the format from the file's extension (Music's
    /// kind tells AAC from Apple Lossless, which share .m4a), then what Music knows of bitrate and sample rate.
    var formatSummary: String? {
        var parts: [String] = []
        let ext = location.pathExtension.lowercased()
        let format: String? = switch ext {
        case "m4a", "mp4", "m4p": kind.localizedCaseInsensitiveContains("lossless") ? "ALAC" : "AAC"
        case "aif", "aiff", "aifc": "AIFF"
        case "": nil
        default: ext.uppercased()
        }
        if let format { parts.append(format) }
        if bitrate > 0 { parts.append("\(bitrate.formatted()) kbps") }
        if sampleRate > 0 {
            let khz = Double(sampleRate) / 1000
            parts.append("\(khz.formatted(.number.precision(.fractionLength(0...1)))) kHz")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
    var stars: Int { rating / 20 }
}

struct Album: Identifiable, Hashable, Sendable {
    let id: PersistentID
    var title: String
    var artist: String
    var year: Int
    var genre: String
    var isCompilation: Bool
    var dateAdded: Date?
    /// Ordered by disc, then track number.
    var trackIDs: [PersistentID]
    var duration: TimeInterval
    var discCount: Int
    /// Bytes on disk, all tracks together.
    var fileSize: Int64 = 0
}

struct Artist: Identifiable, Hashable, Sendable {
    /// Case-folded name; artists are keyed by name since ITLibrary IDs are per-credit.
    let id: String
    var name: String
    var albumIDs: [PersistentID]
    /// Bytes on disk, all their albums together.
    var fileSize: Int64 = 0
}

struct Genre: Identifiable, Hashable, Sendable {
    /// Case-folded name.
    let id: String
    var name: String
    /// In library album order.
    var albumIDs: [PersistentID]
    var trackCount: Int
    /// Bytes on disk, the genre's tracks only.
    var fileSize: Int64 = 0
}

struct LibrarySnapshot: Sendable {
    var tracks: [Track] = []
    var tracksByID: [PersistentID: Track] = [:]
    var albums: [Album] = []
    var albumsByID: [PersistentID: Album] = [:]
    var artists: [Artist] = []
    var artistsByID: [String: Artist] = [:]
    var genres: [Genre] = []
    var genresByID: [String: Genre] = [:]
    /// Per album: title, album artist and every track artist, folded for search.
    var albumSearchText: [PersistentID: String] = [:]

    static let empty = LibrarySnapshot()

    /// Whether `tracks` is exactly what's loaded already. Music reloads (every time Beat becomes active) usually
    /// change nothing, and swapping in an identical snapshot re-ran every element's smart filter.
    func isSameLibrary(tracks other: [Track]) -> Bool { !tracks.isEmpty && tracks == other }

    func tracks(of album: Album) -> [Track] { album.trackIDs.compactMap { tracksByID[$0] } }
    /// The track an album's cover comes from: the first, in album order, that has artwork. Albums whose
    /// tracks each carry different art (a set of singles) show the first one's.
    func artworkTrackID(of album: Album) -> PersistentID? { album.trackIDs.first { tracksByID[$0]?.hasArtwork == true } }
    func hasArtwork(_ album: Album) -> Bool { artworkTrackID(of: album) != nil }

    /// The albums where every typed word appears in the title, album artist or any track artist. Shared by
    /// the Albums grid and its artist list, so both narrow the same way.
    func albums(_ albums: [Album], matching query: String) -> [Album] {
        let words = SearchText.words(query)
        guard !words.isEmpty else { return albums }
        return albums.filter { album in
            SearchText.matches(albumSearchText[album.id] ?? SearchText.fold("\(album.title) \(album.artist)"), words)
        }
    }
    func tracks(of artist: Artist) -> [Track] { artist.albumIDs.compactMap { albumsByID[$0] }.flatMap(tracks(of:)) }
    func tracks(of genre: Genre) -> [Track] {
        genre.albumIDs.compactMap { albumsByID[$0] }.flatMap(tracks(of:)).filter { $0.genre.lowercased() == genre.id }
    }

    /// The key a track's artist is grouped under: its album's artist, which is how artists are indexed.
    func artistKey(_ track: Track) -> String {
        (albumsByID[track.albumID]?.artist ?? track.displayArtist).lowercased()
    }
}

extension LibrarySnapshot {
    static let variousArtists = "Various Artists"

    /// Builds album and artist indexes from flat tracks. Pure, so it's unit-testable without ITLibrary.
    static func build(tracks: [Track]) -> LibrarySnapshot {
        let tracksByID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        var albums: [Album] = Dictionary(grouping: tracks, by: \.albumID).map { albumID, members in
            let ordered = members.sorted {
                ($0.discNumber, $0.trackNumber, $0.title) < ($1.discNumber, $1.trackNumber, $1.title)
            }
            let first = ordered[0]
            let isCompilation = ordered.contains(where: \.isCompilation)
            let artist = ordered.first(where: { !$0.albumArtist.isEmpty })?.albumArtist
                ?? (isCompilation ? variousArtists : first.artist)
            return Album(
                id: albumID,
                title: first.album.isEmpty ? "Unknown Album" : first.album,
                artist: artist.isEmpty ? "Unknown Artist" : artist,
                year: ordered.map(\.year).max() ?? 0,
                genre: first.genre,
                isCompilation: isCompilation,
                dateAdded: ordered.compactMap(\.dateAdded).min(),
                trackIDs: ordered.map(\.id),
                duration: ordered.reduce(0) { $0 + $1.duration },
                discCount: Set(ordered.map(\.discNumber)).count,
                fileSize: ordered.reduce(0) { $0 + $1.fileSize }
            )
        }
        albums.sort {
            let byArtist = $0.artist.localizedStandardCompare($1.artist)
            if byArtist != .orderedSame { return byArtist == .orderedAscending }
            if $0.year != $1.year { return $0.year < $1.year }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }

        var artistsByKey: [String: Artist] = [:]
        for album in albums where !album.isCompilation {
            let key = album.artist.lowercased()
            artistsByKey[key, default: Artist(id: key, name: album.artist, albumIDs: [])].albumIDs.append(album.id)
            artistsByKey[key]?.fileSize += album.fileSize
        }
        let artists = artistsByKey.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var genresByKey: [String: Genre] = [:]
        for album in albums {
            for id in album.trackIDs {
                guard let track = tracksByID[id], !track.genre.isEmpty else { continue }
                let key = track.genre.lowercased()
                var genre = genresByKey[key] ?? Genre(id: key, name: track.genre, albumIDs: [], trackCount: 0)
                genre.trackCount += 1
                genre.fileSize += track.fileSize
                if genre.albumIDs.last != album.id { genre.albumIDs.append(album.id) }
                genresByKey[key] = genre
            }
        }
        let genres = genresByKey.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        // So album search also finds featured artists and the artists on compilations.
        let albumSearchText = Dictionary(albums.map { album in
            var names = [album.title, album.artist]
            for id in album.trackIDs {
                guard let track = tracksByID[id] else { continue }
                for name in [track.artist, track.albumArtist] where !name.isEmpty && !names.contains(name) { names.append(name) }
            }
            return (album.id, SearchText.fold(names.joined(separator: " ")))
        }, uniquingKeysWith: { a, _ in a })

        return LibrarySnapshot(
            tracks: tracks,
            tracksByID: tracksByID,
            albums: albums,
            albumsByID: Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }),
            artists: artists,
            artistsByID: artistsByKey,
            genres: genres,
            genresByID: genresByKey,
            albumSearchText: albumSearchText
        )
    }
}

/// Whose picture to show: an album's cover, or a track's own art where the track is the focus (Now
/// Playing), so an album whose tracks carry different art shows each one as it plays.
enum ArtworkSource: Hashable, Sendable {
    case album(PersistentID)
    case track(PersistentID)

    /// The track's own art, or its album's cover when the track has none.
    init(_ track: Track) {
        self = track.hasArtwork ? .track(track.id) : .album(track.albumID)
    }
}
