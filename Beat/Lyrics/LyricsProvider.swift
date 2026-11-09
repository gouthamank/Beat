import AVFoundation
import SwiftUI

/// Finds lyrics for a track: a `.lrc` file beside it, the lyrics embedded in the file, and (only when
/// the user has opted in) LRCLIB. Never writes to the audio files or to Music.
actor LyricsProvider {
    /// A request's outcome. `failed` (offline, server trouble) isn't an answer and isn't saved.
    private enum Fetched<Value> {
        case found(Value)
        case notFound
        case failed
    }

    private var memory: [String: Lyrics] = [:]
    private let directory: URL?
    private let session: URLSession

    init(directory: URL? = PageStore.defaultDirectory?.appendingPathComponent("lyrics", isDirectory: true),
         session: URLSession = .shared) {
        self.directory = directory
        self.session = session
    }

    /// `online` allows a network lookup; answers already saved on disk are used either way.
    func lyrics(for track: Track, online: Bool) async -> Lyrics {
        let key = "\(track.id)-\(online)"
        if let hit = memory[key] { return hit }

        let sidecar = try? String(contentsOf: track.location.deletingPathExtension().appendingPathExtension("lrc"), encoding: .utf8)
        let embedded = await embeddedLyrics(track.location)
        let remote = LyricsResolver.wantsOnline(sidecar: sidecar, embedded: embedded)
            ? await onlineLyrics(for: track, allowNetwork: online)
            : nil
        let result = LyricsResolver.resolve(sidecar: sidecar, embedded: embedded, online: remote)
        memory[key] = result
        return result
    }

    func clearDownloaded() {
        memory = [:]
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    // MARK: Sources

    /// The ID3 USLT / MP4 ©lyr text Music stores when lyrics are added in Get Info.
    private func embeddedLyrics(_ url: URL) async -> String? {
        let asset = AVURLAsset(url: url)
        let text = (try? await asset.load(.lyrics)) ?? nil
        return text?.isEmpty == false ? text : nil
    }

    private func onlineLyrics(for track: Track, allowNetwork: Bool) async -> LyricsResolver.Online? {
        let file = directory?.appendingPathComponent("\(track.id).json")
        if let file, let data = try? Data(contentsOf: file),
           let cached = try? JSONDecoder().decode(CachedLyrics.self, from: data), cached.isFresh(now: .now) {
            return cached.result
        }
        guard allowNetwork else { return nil }

        let result: LyricsResolver.Online?
        switch await lookUp(track) {
        case .found(let online): result = online
        case .notFound: result = nil
        case .failed: return nil // Ask again next time.
        }
        if let file, let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? JSONEncoder().encode(CachedLyrics(result: result, fetchedAt: .now)).write(to: file, options: .atomic)
        }
        return result
    }

    /// Exact match first, then without the album (tags often carry "(Deluxe)" or a catalogue number that
    /// LRCLIB's copy lacks), then a search on artist and title picked by length.
    private func lookUp(_ track: Track) async -> Fetched<LyricsResolver.Online> {
        for includeAlbum in [true, false] {
            guard let request = Self.getRequest(for: track, includeAlbum: includeAlbum) else { return .failed }
            switch await fetch(LyricsResolver.Record.self, request) {
            case .found(let record): return .found(record.online)
            case .notFound: continue
            case .failed: return .failed
            }
        }
        guard let request = Self.searchRequest(for: track) else { return .failed }
        switch await fetch([LyricsResolver.Record].self, request) {
        case .found(let records):
            return LyricsResolver.bestMatch(records, duration: track.duration).map { .found($0) } ?? .notFound
        case .notFound: return .notFound
        case .failed: return .failed
        }
    }

    private func fetch<Value: Decodable>(_ type: Value.Type, _ request: URLRequest) async -> Fetched<Value> {
        do {
            let (data, response) = try await session.data(for: request)
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200: return .found(try JSONDecoder().decode(Value.self, from: data))
            case 404: return .notFound
            default: return .failed
            }
        } catch {
            return .failed
        }
    }

    /// Sends only artist, title, album and length, which is what LRCLIB matches on.
    static func getRequest(for track: Track, includeAlbum: Bool) -> URLRequest? {
        var items = [
            URLQueryItem(name: "artist_name", value: artistName(track)),
            URLQueryItem(name: "track_name", value: track.title),
        ]
        if includeAlbum { items.append(URLQueryItem(name: "album_name", value: track.album)) }
        items.append(URLQueryItem(name: "duration", value: String(Int(track.duration.rounded()))))
        return request("get", items)
    }

    /// Search takes no length; `LyricsResolver.bestMatch` filters by it afterwards.
    static func searchRequest(for track: Track) -> URLRequest? {
        request("search", [
            URLQueryItem(name: "artist_name", value: artistName(track)),
            URLQueryItem(name: "track_name", value: track.title),
        ])
    }

    private static func artistName(_ track: Track) -> String {
        track.artist.isEmpty ? track.displayArtist : track.artist
    }

    private static func request(_ endpoint: String, _ items: [URLQueryItem]) -> URLRequest? {
        var components = URLComponents(string: "https://lrclib.net/api/\(endpoint)")
        components?.queryItems = items
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        // LRCLIB asks clients to identify themselves.
        request.setValue("Beat (macOS music player)", forHTTPHeaderField: "User-Agent")
        return request
    }
}

extension EnvironmentValues {
    @Entry var lyricsProvider: LyricsProvider? = nil
}
