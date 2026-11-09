import CryptoKit
import Foundation
import SwiftUI

/// Settings for artist info, shared by Settings and the artist page.
enum ArtistInfoSettings {
    /// Off by default: with it off (or without a token) Beat makes no requests to Discogs.
    static let onlineKey = "artistInfo.online"
    static let tokenAccount = "discogs-token"
}

/// Finds an artist on Discogs (with the user's personal token), saves the answer and the photo on this
/// Mac, and serves saved answers afterwards. Mirrors `LyricsProvider`: an answer on disk is used even
/// when lookups are off; the network is only touched when `online` is true and there's a token.
actor ArtistInfoProvider {
    private enum Fetched<Value> {
        case found(Value)
        case notFound
        case failed
    }

    private var memory: [String: ArtistInfo?] = [:]
    private let directory: URL?
    private let session: URLSession

    /// Where answers and photos are saved.
    nonisolated static let defaultDirectory = PageStore.defaultDirectory?.appendingPathComponent("artists", isDirectory: true)

    init(directory: URL? = ArtistInfoProvider.defaultDirectory, session: URLSession = .shared) {
        self.directory = directory
        self.session = session
    }

    /// The artist's info, from memory, disk, or (when allowed) Discogs. `key` is the library's artist ID.
    func info(name: String, key: String, token: String?, online: Bool) async -> ArtistInfo? {
        if let hit = memory[key] { return hit }
        if let cached = readCache(key), cached.isFresh(now: .now) {
            let info = cached.artist.map { ArtistInfo(artist: $0, photo: photoFile(key, exists: true)) }
            memory[key] = info
            return info
        }
        guard online, let token, !token.isEmpty else { return nil }

        switch await fetchSearch(name: name, token: token) {
        case .failed: return nil // Not an answer; ask again next time.
        case .notFound:
            writeCache(key, CachedArtistInfo(artist: nil, fetchedAt: .now))
            memory[key] = .some(nil)
            return nil
        case .found(let results):
            guard let match = ArtistMatcher.best(results, name: name) else {
                writeCache(key, CachedArtistInfo(artist: nil, fetchedAt: .now))
                memory[key] = .some(nil)
                return nil
            }
            return await load(id: match.id, key: key, token: token, chosen: false)
        }
    }

    /// Discogs' candidates for "Wrong artist?".
    func candidates(name: String, token: String) async -> [DiscogsSearchResult] {
        if case .found(let results) = await fetchSearch(name: name, token: token) { return results }
        return []
    }

    /// The user picked a different Discogs artist; it replaces the saved answer.
    func choose(id: Int, key: String, token: String) async -> ArtistInfo? {
        memory[key] = nil
        return await load(id: id, key: key, token: token, chosen: true)
    }

    func clearDownloaded() {
        memory = [:]
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    /// Where an artist's downloaded photo lives (whether or not it exists yet). Synchronous and network-free,
    /// for `ArtistImages`.
    nonisolated static func photoURL(forKey key: String, in directory: URL? = defaultDirectory) -> URL? {
        directory?.appendingPathComponent("\(fileStem(key)).image")
    }

    // MARK: Fetching

    private func load(id: Int, key: String, token: String, chosen: Bool) async -> ArtistInfo? {
        guard let request = Self.artistRequest(id: id, token: token),
              case .found(let artist) = await fetch(DiscogsArtist.self, request) else { return nil }
        var photo: URL?
        let file = photoFile(key, exists: false)
        if let imageURL = artist.primaryImageURL, let file {
            var imageRequest = URLRequest(url: imageURL, timeoutInterval: 15)
            imageRequest.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
            if let (data, response) = try? await session.data(for: imageRequest),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                ensureDirectory()
                if (try? data.write(to: file, options: .atomic)) != nil { photo = file }
            }
        }
        // A photo saved for an earlier match belongs to that artist, not this one: after "Wrong artist?"
        // picks someone without a photo (or theirs fails to download), the mosaic comes back.
        if photo == nil, let file { try? FileManager.default.removeItem(at: file) }
        writeCache(key, CachedArtistInfo(artist: artist, fetchedAt: .now, chosenID: chosen ? id : nil))
        let info = ArtistInfo(artist: artist, photo: photo)
        memory[key] = info
        return info
    }

    private func fetchSearch(name: String, token: String) async -> Fetched<[DiscogsSearchResult]> {
        guard let request = Self.searchRequest(name: name, token: token) else { return .failed }
        switch await fetch(DiscogsSearchResponse.self, request) {
        case .found(let response): return response.results.isEmpty ? .notFound : .found(response.results)
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

    // Discogs asks every client to identify itself; the token authorises search and image URLs.
    static let userAgent = "Beat/1.0 (macOS music player)"

    static func searchRequest(name: String, token: String) -> URLRequest? {
        var components = URLComponents(string: "https://api.discogs.com/database/search")
        components?.queryItems = [URLQueryItem(name: "type", value: "artist"), URLQueryItem(name: "q", value: name)]
        return components?.url.map { request($0, token: token) }
    }

    static func artistRequest(id: Int, token: String) -> URLRequest? {
        URL(string: "https://api.discogs.com/artists/\(id)").map { request($0, token: token) }
    }

    private static func request(_ url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: Disk

    /// Artist IDs are names, so files are named by a hash of the ID.
    private nonisolated static func fileStem(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private func readCache(_ key: String) -> CachedArtistInfo? {
        guard let file = directory?.appendingPathComponent("\(Self.fileStem(key)).json"),
              let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(CachedArtistInfo.self, from: data)
    }

    private func writeCache(_ key: String, _ cached: CachedArtistInfo) {
        guard let file = directory?.appendingPathComponent("\(Self.fileStem(key)).json") else { return }
        ensureDirectory()
        try? JSONEncoder().encode(cached).write(to: file, options: .atomic)
    }

    private func photoFile(_ key: String, exists: Bool) -> URL? {
        guard let file = Self.photoURL(forKey: key, in: directory) else { return nil }
        return !exists || FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    private func ensureDirectory() {
        if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    }
}

extension EnvironmentValues {
    @Entry var artistInfoProvider: ArtistInfoProvider? = nil
}

