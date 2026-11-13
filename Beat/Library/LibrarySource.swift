import Foundation

/// Where the library comes from: Music on the Mac (`LibraryLoader`, iTunesLibrary), the songs synced to an iPad or
/// iPhone (`MediaLibrarySource`, MediaPlayer), or audio files in Beat's Documents folder (`FolderLibrarySource`, for
/// the Simulator, which has no music library). Each owns its platform objects and hands out Sendable snapshots and
/// artwork bytes. `makeLibrarySource()`, defined per platform, picks one.
protocol LibrarySource: Actor {
    /// Asks for access where the platform needs it first (MediaPlayer). Returns whether access was given.
    func requestAccess() async -> Bool
    func load() async throws -> LibrarySnapshot
    /// Art is known only once the library has been read; requests before that wait for the first read.
    func artworkData(for source: ArtworkSource) async -> Data?
}

extension LibrarySource {
    func requestAccess() async -> Bool { true }
}

/// Lets art requests wait until a source has read its library once: asked earlier (while a saved library is on
/// screen), they would find nothing and never ask again.
struct FirstLoadGate {
    private(set) var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    mutating func wait(_ continuation: CheckedContinuation<Void, Never>) {
        if isOpen { continuation.resume() } else { waiting.append(continuation) }
    }

    mutating func open() {
        guard !isOpen else { return }
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

/// A song's fields as a platform library reports them, before they become a `Track`: plain values, so the mapping
/// is the same for every source and can be tested without MediaPlayer or AVFoundation objects.
struct MediaItemFields: Sendable {
    var id: PersistentID
    var title: String?
    var artist: String?
    var albumArtist: String?
    var album: String?
    var albumID: PersistentID
    var composer: String?
    var genre: String?
    var grouping: String?
    var comments: String?
    var year: Int = 0
    /// Stars, 0–5 (MediaPlayer's scale); `Track.rating` is 0–100.
    var stars: Int = 0
    var playCount: Int = 0
    var skipCount: Int = 0
    var bpm: Int = 0
    var trackNumber: Int = 0
    var discNumber: Int = 0
    var duration: TimeInterval = 0
    var dateAdded: Date?
    var lastPlayed: Date?
    var isCompilation = false
    var hasArtwork = false
    var location: URL?
    var kind = ""
    var bitrate = 0
    var sampleRate = 0
    var fileSize: Int64 = 0

    /// The track, or nil without a playable file: DRM and cloud-only songs have none, and are skipped as on the Mac.
    var track: Track? {
        guard let location else { return nil }
        return Track(
            id: id,
            title: title?.nilIfEmpty ?? location.deletingPathExtension().lastPathComponent,
            artist: artist ?? "",
            albumArtist: albumArtist ?? "",
            album: album ?? "",
            albumID: albumID,
            composer: composer ?? "",
            genre: genre ?? "",
            kind: kind,
            comments: comments ?? "",
            grouping: grouping ?? "",
            year: year,
            rating: min(max(stars, 0), 5) * 20,
            playCount: playCount,
            skipCount: skipCount,
            bpm: bpm,
            bitrate: bitrate,
            sampleRate: sampleRate,
            trackNumber: trackNumber,
            discNumber: max(discNumber, 1),
            duration: duration,
            dateAdded: dateAdded,
            dateModified: nil,
            lastPlayed: lastPlayed,
            lastSkipped: nil,
            isCompilation: isCompilation,
            hasArtwork: hasArtwork,
            location: location,
            fileSize: fileSize
        )
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
