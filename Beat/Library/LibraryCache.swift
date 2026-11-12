import Foundation

/// The library as last read from Music, saved so the next launch shows it at once while the real read runs
/// behind it: reading Music's ~20k songs through ITLibrary took about 4 s, this about 0.4 s (JSON decoded faster
/// than a binary plist). A cache only, in Caches: when it's missing, unreadable or from an older Beat, launch
/// simply waits for Music as before.
enum LibraryCache {
    /// Raise when `Track` changes shape; an older file is then ignored and replaced.
    static let schema = 1

    private struct Contents: Codable {
        var schema: Int
        var tracks: [Track]
    }

    nonisolated static var directory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Beat", isDirectory: true)
    }

    private nonisolated static var file: URL? { directory?.appendingPathComponent("library.json") }

    nonisolated static func encode(_ tracks: [Track]) throws -> Data {
        try JSONEncoder().encode(Contents(schema: schema, tracks: tracks))
    }

    /// The saved tracks, or nil for anything unreadable or saved by a different schema.
    nonisolated static func decode(_ data: Data) -> [Track]? {
        guard let contents = try? JSONDecoder().decode(Contents.self, from: data), contents.schema == schema else { return nil }
        return contents.tracks
    }

    /// The saved library, built and ready to show; nil when there's none usable (a bad file is deleted).
    @concurrent
    nonisolated static func load() async -> LibrarySnapshot? {
        guard let file, let data = try? Data(contentsOf: file) else { return nil }
        guard let tracks = decode(data), !tracks.isEmpty else {
            try? FileManager.default.removeItem(at: file)
            return nil
        }
        return LibrarySnapshot.build(tracks: tracks)
    }

    @concurrent
    nonisolated static func save(_ tracks: [Track]) async {
        guard let directory, let file, let data = try? encode(tracks) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    nonisolated static func remove() {
        if let file { try? FileManager.default.removeItem(at: file) }
    }
}
