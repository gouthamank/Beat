import CoreFoundation
import Foundation

/// A settings file, for moving Beat to another Mac or keeping a backup: the sidebar's folders and pages
/// (definitions only: smart filters, layouts and custom fields, never tracks, which are found live in the
/// library) plus Beat's preferences. Importing replaces both.
///
/// Left out on purpose: the Discogs token (a secret, kept in the Keychain), play history (data, not
/// settings), downloaded caches, and window state (volume, the selected page, expanded folders).
struct SettingsArchive: Codable {
    static let format = "beat-settings"

    /// The preferences a settings file carries. Any of them missing from a file goes back to its default.
    static let preferenceKeys = [
        "appearance.coverColours",
        SidebarTint.key,
        "lyrics.online",
        ArtistInfoSettings.onlineKey,
        LibraryPage.hiddenKey,
        ArtistSorts.storageKey,
        NewElementDefaults.key,
        "songs.showCovers",
        "songs.albumColumns",
        "songs.albumArtWidth",
        "albums.artistList",
        "visualizer.enabled",
        "visualizer.style",
        "nowPlaying.showLyrics",
    ]

    enum ArchiveError: LocalizedError {
        case notASettingsFile
        case newerVersion(Int)

        var errorDescription: String? {
            switch self {
            case .notASettingsFile: "This file isn't a Beat settings file."
            case .newerVersion: "This settings file was made by a newer version of Beat."
            }
        }
    }

    var format = SettingsArchive.format
    var version = 1
    var exportedAt: Date
    var nodes: [SidebarNode]
    var customFields: [CustomField]
    var preferences: [String: Preference]

    /// A preference value as UserDefaults stores it.
    enum Preference: Codable, Equatable {
        case bool(Bool)
        case int(Int)
        case double(Double)
        case string(String)
        case data(Data)

        private struct Wrapped: Codable { var base64: Data }

        /// Plain JSON values, so the file stays readable; data (encoded sorts and defaults) as base64.
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let v = try? c.decode(Bool.self) { self = .bool(v) }
            else if let v = try? c.decode(Int.self) { self = .int(v) }
            else if let v = try? c.decode(Double.self) { self = .double(v) }
            else if let v = try? c.decode(String.self) { self = .string(v) }
            else { self = .data(try c.decode(Wrapped.self).base64) }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.singleValueContainer()
            switch self {
            case .bool(let v): try c.encode(v)
            case .int(let v): try c.encode(v)
            case .double(let v): try c.encode(v)
            case .string(let v): try c.encode(v)
            case .data(let v): try c.encode(Wrapped(base64: v))
            }
        }

        init?(_ value: Any) {
            switch value {
            case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): self = .bool(number.boolValue)
            case let number as NSNumber where CFNumberIsFloatType(number as CFNumber): self = .double(number.doubleValue)
            case let number as NSNumber: self = .int(number.intValue)
            case let string as String: self = .string(string)
            case let data as Data: self = .data(data)
            default: return nil
            }
        }

        var value: Any {
            switch self {
            case .bool(let v): v
            case .int(let v): v
            case .double(let v): v
            case .string(let v): v
            case .data(let v): v
            }
        }
    }

    static func capture(nodes: [SidebarNode], customFields: [CustomField], defaults: UserDefaults, now: Date = .now) -> SettingsArchive {
        var preferences: [String: Preference] = [:]
        for key in preferenceKeys {
            if let value = defaults.object(forKey: key).flatMap(Preference.init) { preferences[key] = value }
        }
        return SettingsArchive(exportedAt: now, nodes: nodes, customFields: customFields, preferences: preferences)
    }

    /// Replaces Beat's preferences with the file's. Keys the file doesn't have go back to their defaults;
    /// keys it has that Beat doesn't know are ignored.
    func applyPreferences(to defaults: UserDefaults) {
        for key in Self.preferenceKeys {
            if let preference = preferences[key] {
                defaults.set(preference.value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> SettingsArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        struct Header: Decodable { var format: String?; var version: Int? }
        guard let header = try? decoder.decode(Header.self, from: data), header.format == format else {
            throw ArchiveError.notASettingsFile
        }
        if let version = header.version, version > 1 { throw ArchiveError.newerVersion(version) }
        return try decoder.decode(SettingsArchive.self, from: data)
    }
}
