import Foundation
import MediaPlayer
import UIKit

/// On iPad and iPhone: the songs synced to the device from a Mac (Finder sync), read through MediaPlayer. Songs
/// without a playable file (Apple Music DRM, cloud-only) have no `assetURL` and are skipped, as songs without a
/// file location are on the Mac. MediaPlayer doesn't report bitrate, sample rate, file size or kind, so what
/// depends on them hides itself.
actor MediaLibrarySource: LibrarySource {
    enum LoadError: LocalizedError {
        case accessDenied

        var errorDescription: String? {
            "Beat couldn't open your music library. Allow access in Settings › Privacy & Security › Media & Apple Music."
        }
    }

    /// Songs with artwork, so art is fetched lazily: a song's own, or its album's cover song's.
    private var trackArtwork: [PersistentID: MPMediaItem] = [:]
    private var albumArtwork: [PersistentID: MPMediaItem] = [:]
    private var gate = FirstLoadGate()

    func requestAccess() async -> Bool {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized: return true
        case .notDetermined: return await MPMediaLibrary.requestAuthorization() == .authorized
        default: return false
        }
    }

    func load() async throws -> LibrarySnapshot {
        defer { gate.open() }
        guard MPMediaLibrary.authorizationStatus() == .authorized else { throw LoadError.accessDenied }
        var tracks: [Track] = []
        var trackArtwork: [PersistentID: MPMediaItem] = [:]
        for item in MPMediaQuery.songs().items ?? [] {
            guard let track = Self.fields(item).track else { continue }
            tracks.append(track)
            if track.hasArtwork { trackArtwork[track.id] = item }
        }
        let snapshot = LibrarySnapshot.build(tracks: tracks)
        var albumArtwork: [PersistentID: MPMediaItem] = [:]
        for album in snapshot.albums {
            if let id = snapshot.artworkTrackID(of: album) { albumArtwork[album.id] = trackArtwork[id] }
        }
        self.trackArtwork = trackArtwork
        self.albumArtwork = albumArtwork
        return snapshot
    }

    func artworkData(for source: ArtworkSource) async -> Data? {
        if !gate.isOpen { await withCheckedContinuation { gate.wait($0) } }
        let item: MPMediaItem? = switch source {
        case .album(let id): albumArtwork[id]
        case .track(let id): trackArtwork[id]
        }
        guard let artwork = item?.artwork else { return nil }
        // The largest Beat shows (the full-window viewer); `ArtworkCache` scales it down for each size.
        let side = min(max(artwork.bounds.width, artwork.bounds.height), 4096)
        return artwork.image(at: CGSize(width: max(side, 600), height: max(side, 600)))?.jpegData(compressionQuality: 0.92)
    }

    /// The year tag, as Music shows it. `releaseDate` is only set for Apple Music downloads: synced songs had none,
    /// so every year read 0 ("No year"). The tag itself is MediaPlayer's undocumented "year" property.
    static func year(of item: MPMediaItem) -> Int {
        if let year = (item.value(forProperty: "year") as? NSNumber)?.intValue, year > 0 { return year }
        return item.releaseDate.map { Calendar.current.component(.year, from: $0) } ?? 0
    }

    private static func fields(_ item: MPMediaItem) -> MediaItemFields {
        MediaItemFields(
            id: item.persistentID,
            title: item.title,
            artist: item.artist,
            albumArtist: item.albumArtist,
            album: item.albumTitle,
            albumID: item.albumPersistentID,
            composer: item.composer,
            genre: item.genre,
            grouping: item.userGrouping,
            comments: item.comments,
            year: Self.year(of: item),
            stars: item.rating,
            playCount: item.playCount,
            skipCount: item.skipCount,
            bpm: item.beatsPerMinute,
            trackNumber: item.albumTrackNumber,
            discNumber: item.discNumber,
            duration: item.playbackDuration,
            dateAdded: item.dateAdded,
            lastPlayed: item.lastPlayedDate,
            isCompilation: item.isCompilation,
            hasArtwork: item.artwork != nil,
            location: item.assetURL
        )
    }
}
