import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Which picture a source shows, as far as Music says: the song its art comes from and when that song last
/// changed. Changing only the artwork in Music bumps the song's modified date (checked against Music, Nov 2026),
/// so a different label means a possibly different picture.
struct ArtworkLabel: Hashable, Sendable {
    let trackID: PersistentID
    /// Seconds since 1970 of the song's `dateModified`; 0 when Music gives none.
    let modified: Int
}

extension LibrarySnapshot {
    /// The label for a source's art now, or nil when it has none (or is gone from the library).
    func artworkLabel(for source: ArtworkSource) -> ArtworkLabel? {
        let track: Track?
        switch source {
        case .album(let id): track = albumsByID[id].flatMap(artworkTrackID(of:)).flatMap { tracksByID[$0] }
        case .track(let id): track = tracksByID[id].flatMap { $0.hasArtwork ? $0 : nil }
        }
        return track.map { ArtworkLabel(trackID: $0.id, modified: Int($0.dateModified?.timeIntervalSince1970 ?? 0)) }
    }

    /// The sources whose art may have changed between two reads of Music: the cover moved to another song, the
    /// cover song was modified, or the album or song is gone. Only sources that had art before; new ones have
    /// nothing cached to throw away.
    static func changedArtwork(old: LibrarySnapshot, new: LibrarySnapshot) -> Set<ArtworkSource> {
        var changed = Set<ArtworkSource>()
        for album in old.albums {
            let source = ArtworkSource.album(album.id)
            if let label = old.artworkLabel(for: source), new.artworkLabel(for: source) != label { changed.insert(source) }
        }
        for track in old.tracks where track.hasArtwork {
            let source = ArtworkSource.track(track.id)
            if let label = old.artworkLabel(for: source), new.artworkLabel(for: source) != label { changed.insert(source) }
        }
        return changed
    }
}

/// Cover thumbnails (`ArtworkCache.Size.thumbnail`) saved as HEIC, so covers appear at launch before Music's
/// library has been read (about 4 s). Each file is named for its source and label, so a changed cover simply has
/// a different name: a stale file is never read, and is deleted when it's noticed. About 30 KB a cover.
/// A cache only, in Caches: anything missing is fetched from Music again.
actor ArtworkDiskCache {
    private let directory: URL?
    /// File names on disk, listed once rather than asking the file system on every lookup.
    private var names: Set<String>?

    init(directory: URL? = LibraryCache.directory?.appendingPathComponent("Thumbnails", isDirectory: true)) {
        self.directory = directory
    }

    nonisolated static func name(for source: ArtworkSource, label: ArtworkLabel) -> String {
        "\(prefix(for: source))\(label.trackID)_\(label.modified).heic"
    }

    /// Every file for a source starts with this, whatever its label.
    nonisolated static func prefix(for source: ArtworkSource) -> String {
        switch source {
        case .album(let id): "a\(id)_"
        case .track(let id): "t\(id)_"
        }
    }

    func image(for source: ArtworkSource, label: ArtworkLabel) -> CGImage? {
        let name = Self.name(for: source, label: label)
        guard let directory, listed().contains(name),
              let image = CGImageSourceCreateWithURL(directory.appendingPathComponent(name) as CFURL, nil)
                  .flatMap({ CGImageSourceCreateImageAtIndex($0, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) })
        else { return nil }
        return image
    }

    /// Saves a thumbnail, replacing any older one for the same source.
    func store(_ image: CGImage, for source: ArtworkSource, label: ArtworkLabel) {
        guard let directory else { return }
        remove(source)
        let name = Self.name(for: source, label: label)
        let url = directory.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        if CGImageDestinationFinalize(destination) { names?.insert(name) }
    }

    func remove(_ source: ArtworkSource) {
        let prefix = Self.prefix(for: source)
        for name in listed() where name.hasPrefix(prefix) { delete(name) }
    }

    /// Deletes thumbnails whose source is gone or whose label no longer matches `current`: covers that changed
    /// in Music while Beat was closed, and albums since removed.
    func prune(keeping library: LibrarySnapshot) {
        for name in listed() {
            let current = Self.source(of: name).flatMap { source in
                library.artworkLabel(for: source).map { Self.name(for: source, label: $0) }
            }
            if current != name { delete(name) }
        }
    }

    func removeAll() {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        names = []
    }

    /// The source a file name was saved for.
    nonisolated static func source(of name: String) -> ArtworkSource? {
        guard let kind = name.first, let id = PersistentID(name.dropFirst().prefix { $0 != "_" }) else { return nil }
        switch kind {
        case "a": return .album(id)
        case "t": return .track(id)
        default: return nil
        }
    }

    private func listed() -> Set<String> {
        if let names { return names }
        let found = directory.flatMap { try? FileManager.default.contentsOfDirectory(atPath: $0.path) } ?? []
        let set = Set(found.filter { $0.hasSuffix(".heic") })
        names = set
        return set
    }

    private func delete(_ name: String) {
        if let directory { try? FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
        names?.remove(name)
    }
}
