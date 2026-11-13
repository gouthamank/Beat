import Foundation
import iTunesLibrary

/// The Mac's library source: owns the (non-Sendable) ITLibrary and hands out Sendable snapshots and artwork bytes.
actor LibraryLoader: LibrarySource {
    enum LoadError: LocalizedError {
        case accessDenied(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                "Beat couldn't open your Music library. Allow access in System Settings › Privacy & Security › Media & Apple Music."
            }
        }
    }

    private var library: ITLibrary?
    /// Tracks with artwork, so art is fetched lazily: a track's own, or its album's cover.
    private var trackArtwork: [PersistentID: ITLibMediaItem] = [:]
    /// Each album's cover track (see `LibrarySnapshot.artworkTrackID`).
    private var albumArtwork: [PersistentID: ITLibMediaItem] = [:]
    /// Music has been read once (or the read failed), so art requests can be answered.
    private var firstLoadFinished = false
    private var waitingForFirstLoad: [CheckedContinuation<Void, Never>] = []

    private func finishFirstLoad() {
        guard !firstLoadFinished else { return }
        firstLoadFinished = true
        waitingForFirstLoad.forEach { $0.resume() }
        waitingForFirstLoad = []
    }

    func load() throws -> LibrarySnapshot {
        defer { finishFirstLoad() }
        let library: ITLibrary
        if let existing = self.library {
            existing.reloadData()
            library = existing
        } else {
            do {
                library = try ITLibrary(apiVersion: "1.1")
            } catch {
                throw LoadError.accessDenied(underlying: error)
            }
            self.library = library
        }

        var tracks: [Track] = []
        var trackArtwork: [PersistentID: ITLibMediaItem] = [:]
        for item in library.allMediaItems {
            guard item.mediaKind == .kindSong, !item.isVideo, let location = item.location else { continue }
            let track = Self.makeTrack(item, location: location)
            tracks.append(track)
            if item.hasArtworkAvailable { trackArtwork[track.id] = item }
        }
        let snapshot = LibrarySnapshot.build(tracks: tracks)
        var albumArtwork: [PersistentID: ITLibMediaItem] = [:]
        for album in snapshot.albums {
            if let id = snapshot.artworkTrackID(of: album) { albumArtwork[album.id] = trackArtwork[id] }
        }
        self.trackArtwork = trackArtwork
        self.albumArtwork = albumArtwork
        return snapshot
    }

    /// Art is known only once Music has been read. While a saved library is on screen, cover requests wait for
    /// that first read instead of finding nothing (and never asking again).
    func artworkData(for source: ArtworkSource) async -> Data? {
        if !firstLoadFinished { await withCheckedContinuation { waitingForFirstLoad.append($0) } }
        return switch source {
        case .album(let id): albumArtwork[id]?.artwork?.imageData
        case .track(let id): trackArtwork[id]?.artwork?.imageData
        }
    }

    private static func makeTrack(_ item: ITLibMediaItem, location: URL) -> Track {
        Track(
            id: item.persistentID.uint64Value,
            title: item.title,
            artist: item.artist?.name ?? "",
            albumArtist: item.album.albumArtist ?? "",
            album: item.album.title ?? "",
            albumID: item.album.persistentID.uint64Value,
            composer: item.composer,
            genre: item.genre,
            kind: item.kind ?? "",
            comments: item.comments ?? "",
            grouping: item.grouping ?? "",
            year: item.year,
            rating: item.isRatingComputed ? 0 : item.rating,
            playCount: item.playCount,
            skipCount: item.skipCount,
            bpm: item.beatsPerMinute,
            bitrate: item.bitrate,
            sampleRate: item.sampleRate,
            trackNumber: item.trackNumber,
            discNumber: max(item.album.discNumber, 1),
            duration: TimeInterval(item.totalTime) / 1000,
            dateAdded: item.addedDate,
            dateModified: item.modifiedDate,
            lastPlayed: item.lastPlayedDate,
            lastSkipped: item.skipDate,
            isCompilation: item.album.isCompilation,
            hasArtwork: item.hasArtworkAvailable,
            location: location,
            fileSize: Int64(clamping: item.fileSize)
        )
    }
}

/// On the Mac, the library is Music's, read through iTunesLibrary.
func makeLibrarySource() -> any LibrarySource { LibraryLoader() }
