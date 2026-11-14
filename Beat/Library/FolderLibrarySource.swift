import AVFoundation
import Foundation

/// A library made of the audio files in Beat's Documents folder, for the Simulator: it has no music library and
/// Finder can't sync to it. Files dropped onto the Simulator and saved to Files ▸ On My iPad ▸ Beat show up after
/// a relaunch, with tags and artwork read from the files themselves. Shared rather than iOS-only so tests on both
/// platforms can read a folder of fixture files.
actor FolderLibrarySource: LibrarySource {
    private let folder: URL?
    /// Off for a UI test's fixture folder, which is in the repo.
    private let makesMusicFolder: Bool
    /// Embedded artwork per song (and per album, its first song's), read during the load.
    private var trackArtwork: [PersistentID: Data] = [:]
    private var albumArtwork: [PersistentID: Data] = [:]
    private var gate = FirstLoadGate()

    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac", "alac"]

    init(folder: URL? = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
         makesMusicFolder: Bool = true) {
        self.folder = folder
        self.makesMusicFolder = makesMusicFolder
    }

    func load() async throws -> LibrarySnapshot {
        defer { gate.open() }
        // Files lists an app's folder only once it has something in it; an empty "Music" folder makes "Beat"
        // appear under On My iPad, with a place to drop songs. (The whole folder is read, subfolders included.)
        if let folder, makesMusicFolder {
            try? FileManager.default.createDirectory(at: folder.appendingPathComponent("Music", isDirectory: true),
                                                     withIntermediateDirectories: true)
        }
        guard let folder,
              let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .addedToDirectoryDateKey])
        else { return .build(tracks: []) }
        let files = walker.compactMap { $0 as? URL }.filter(Self.isAudio)
        var tracks: [Track] = []
        var trackArtwork: [PersistentID: Data] = [:]
        for file in files {
            var (fields, art) = await Self.fields(file, in: folder)
            fields.hasArtwork = art != nil
            guard let track = fields.track else { continue }
            tracks.append(track)
            if let art { trackArtwork[track.id] = art }
        }
        let snapshot = LibrarySnapshot.build(tracks: tracks)
        var albumArtwork: [PersistentID: Data] = [:]
        for album in snapshot.albums {
            if let id = snapshot.artworkTrackID(of: album) { albumArtwork[album.id] = trackArtwork[id] }
        }
        self.trackArtwork = trackArtwork
        self.albumArtwork = albumArtwork
        return snapshot
    }

    func artworkData(for source: ArtworkSource) async -> Data? {
        if !gate.isOpen { await withCheckedContinuation { gate.wait($0) } }
        return switch source {
        case .album(let id): albumArtwork[id]
        case .track(let id): trackArtwork[id]
        }
    }

    static func isAudio(_ file: URL) -> Bool { audioExtensions.contains(file.pathExtension.lowercased()) }

    /// What songs of one album share, however their tags are cased: the album artist (else the artist) and album.
    static func albumKey(albumArtist: String?, artist: String?, album: String?) -> String {
        "\(albumArtist ?? artist ?? "")\u{1F}\(album ?? "")".lowercased()
    }

    /// The year from a year or date tag ("2011", "2011-05-02"); 0 without one.
    static func year(from text: String?) -> Int { text.flatMap { Int($0.prefix(4)) } ?? 0 }

    /// The track number from a tag that may carry the total too ("3/12"); 0 without one.
    static func trackNumber(from text: String?) -> Int {
        text.flatMap { Int($0.split(separator: "/").first ?? "") } ?? 0
    }

    /// The track number from an iTunes (MP4) `trkn` tag: two bytes of padding, then the number and the total as
    /// big-endian 16-bit values; 0 when it's too short.
    static func trackNumber(fromITunes data: Data) -> Int {
        let bytes = [UInt8](data)
        guard bytes.count >= 4 else { return 0 }
        return Int(bytes[2]) << 8 | Int(bytes[3])
    }

    /// A stable ID from text (FNV-1a), so a song or album keeps its ID across launches, as Music's IDs do.
    static func stableID(_ text: String) -> PersistentID {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        return hash
    }

    private static func fields(_ file: URL, in folder: URL) async -> (MediaItemFields, Data?) {
        let asset = AVURLAsset(url: file)
        let metadata = (try? await asset.load(.metadata)) ?? []
        /// The first non-empty value among `ids`, in order: ID3, iTunes and QuickTime files name the same tag differently.
        func text(_ ids: [AVMetadataIdentifier]) async -> String? {
            for id in ids {
                for item in AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: id) {
                    if let value = try? await item.load(.stringValue), !value.isEmpty { return value }
                }
            }
            return nil
        }
        let title = await text([.commonIdentifierTitle, .id3MetadataTitleDescription, .iTunesMetadataSongName])
        let artist = await text([.commonIdentifierArtist, .id3MetadataLeadPerformer, .iTunesMetadataArtist])
        let albumArtist = await text([.id3MetadataBand, .iTunesMetadataAlbumArtist])
        let album = await text([.commonIdentifierAlbumName, .id3MetadataAlbumTitle, .iTunesMetadataAlbum])
        let genre = await text([.id3MetadataContentType, .iTunesMetadataUserGenre, .quickTimeMetadataGenre])
        let yearText = await text([.id3MetadataYear, .id3MetadataRecordingTime, .iTunesMetadataReleaseDate, .commonIdentifierCreationDate])
        let trackText = await text([.id3MetadataTrackNumber])
        var trackData: Data?
        for item in AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .iTunesMetadataTrackNumber) {
            if let data = try? await item.load(.dataValue) { trackData = data; break }
        }
        var artwork: Data?
        for item in AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork) {
            if let data = try? await item.load(.dataValue) { artwork = data; break }
        }
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        let values = try? file.resourceValues(forKeys: [.fileSizeKey, .addedToDirectoryDateKey])
        let relative = String(file.path.dropFirst(folder.path.count))
        return (MediaItemFields(
            id: stableID(relative),
            title: title,
            artist: artist,
            albumArtist: albumArtist,
            album: album,
            albumID: stableID(albumKey(albumArtist: albumArtist, artist: artist, album: album)),
            genre: genre,
            year: year(from: yearText),
            trackNumber: trackText.map { trackNumber(from: $0) } ?? trackData.map(trackNumber(fromITunes:)) ?? 0,
            duration: duration.isFinite ? duration : 0,
            dateAdded: values?.addedToDirectoryDate,
            location: file,
            kind: file.pathExtension.uppercased(),
            fileSize: Int64(values?.fileSize ?? 0)
        ), artwork)
    }
}
