import Foundation
import Observation

/// Plays and skips recorded by Beat. Stored locally and never written to the Music library;
/// smart filters merge these stats with Music's own counts.
@MainActor
@Observable
final class PlayHistoryStore {
    struct Stats: Codable, Equatable, Sendable {
        var playCount = 0
        var lastPlayed: Date?
        var skipCount = 0
        var lastSkipped: Date?
    }

    private(set) var stats: [PersistentID: Stats] = [:]
    /// Bumped on every change; used as a cache key by derived results.
    private(set) var version = 0

    @ObservationIgnored private let fileURL: URL?

    init(fileURL: URL? = PlayHistoryStore.defaultURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([PersistentID: Stats].self, from: data) {
            stats = decoded
        }
    }

    func recordPlay(_ id: PersistentID, at date: Date = .now) {
        stats[id, default: Stats()].playCount += 1
        stats[id]?.lastPlayed = date
        changed()
    }

    func recordSkip(_ id: PersistentID, at date: Date = .now) {
        stats[id, default: Stats()].skipCount += 1
        stats[id]?.lastSkipped = date
        changed()
    }

    /// The track with Beat's plays and skips folded into Music's stats.
    func merged(_ track: Track) -> Track {
        guard let s = stats[track.id] else { return track }
        var t = track
        t.playCount += s.playCount
        t.skipCount += s.skipCount
        t.lastPlayed = [t.lastPlayed, s.lastPlayed].compactMap { $0 }.max()
        t.lastSkipped = [t.lastSkipped, s.lastSkipped].compactMap { $0 }.max()
        return t
    }

    private func changed() {
        version += 1
        guard let fileURL, let data = try? JSONEncoder().encode(stats) else { return }
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    nonisolated static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Beat", isDirectory: true)
            .appendingPathComponent("history.json")
    }
}
