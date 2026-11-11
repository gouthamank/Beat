import Foundation

/// One play for Last.fm, captured when Beat counted it.
struct Scrobble: Codable, Equatable, Sendable {
    var artist: String
    var track: String
    var album: String
    /// Empty when it's the same as `artist`, so Last.fm isn't sent a redundant field.
    var albumArtist: String
    var trackNumber: Int
    /// Whole seconds.
    var duration: Int
    /// When the song started playing: Last.fm wants the start, not the moment it was counted.
    var timestamp: Date

    /// Nil for what Last.fm won't take: songs of 30 seconds or less, and songs without an artist or title.
    init?(_ track: Track, startedAt: Date) {
        let artist = track.displayArtist.trimmingCharacters(in: .whitespaces)
        let title = track.title.trimmingCharacters(in: .whitespaces)
        guard track.duration > 30, !artist.isEmpty, !title.isEmpty else { return nil }
        self.artist = artist
        self.track = title
        album = track.album
        albumArtist = track.albumArtist == artist ? "" : track.albumArtist
        trackNumber = track.trackNumber
        duration = Int(track.duration.rounded())
        timestamp = startedAt
    }

    /// Last.fm's field names, suffixed with `[index]` in a batch. Empty optional fields are left out, and
    /// a now-playing update (no index) has no timestamp.
    func fields(index: Int?) -> [String: String] {
        let suffix = index.map { "[\($0)]" } ?? ""
        var fields = ["artist\(suffix)": artist, "track\(suffix)": track, "duration\(suffix)": String(duration)]
        if index != nil { fields["timestamp\(suffix)"] = String(Int(timestamp.timeIntervalSince1970)) }
        if !album.isEmpty { fields["album\(suffix)"] = album }
        if !albumArtist.isEmpty { fields["albumArtist\(suffix)"] = albumArtist }
        if trackNumber > 0 { fields["trackNumber\(suffix)"] = String(trackNumber) }
        return fields
    }
}

/// Plays waiting to be sent, oldest first. Saved on disk, so plays made offline or before a crash still
/// reach Last.fm.
struct ScrobbleQueue: Codable, Equatable, Sendable {
    /// The most Last.fm takes in one request.
    static let batchSize = 50
    /// Last.fm refuses scrobbles older than this.
    static let maxAge: TimeInterval = 14 * 86_400

    private(set) var pending: [Scrobble] = []

    mutating func enqueue(_ scrobble: Scrobble) { pending.append(scrobble) }

    var nextBatch: [Scrobble] { Array(pending.prefix(Self.batchSize)) }

    /// Removes what was sent. Plays queued while the request was in flight stay.
    mutating func remove(_ batch: [Scrobble]) {
        for scrobble in batch {
            if let i = pending.firstIndex(of: scrobble) { pending.remove(at: i) }
        }
    }

    mutating func dropExpired(now: Date) {
        pending.removeAll { now.timeIntervalSince($0.timestamp) > Self.maxAge }
    }
}
