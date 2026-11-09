import Foundation

// Artist info from Discogs, shown in the artist page's inspector. Only fetched when the user turns it
// on in Settings and gives Beat their own Discogs token; see `ArtistInfoProvider`.

/// One artist in Discogs' search results.
struct DiscogsSearchResult: Codable, Hashable, Identifiable, Sendable {
    var id: Int
    var title: String
    var thumb: String?
}

struct DiscogsSearchResponse: Decodable, Sendable {
    var results: [DiscogsSearchResult]
}

/// An artist as Discogs describes them (`GET /artists/{id}`), keeping only what the inspector shows.
struct DiscogsArtist: Codable, Hashable, Sendable {
    struct Reference: Codable, Hashable, Sendable {
        var id: Int
        var name: String
        var active: Bool?
    }

    struct Image: Codable, Hashable, Sendable {
        var type: String
        var uri: String
    }

    var id: Int
    var name: String
    var realname: String?
    var profile: String?
    var urls: [String]?
    var aliases: [Reference]?
    var members: [Reference]?
    var groups: [Reference]?
    var images: [Image]?
    /// The artist's page on discogs.com, for the credit link.
    var uri: String?

    var primaryImageURL: URL? {
        (images?.first { $0.type == "primary" } ?? images?.first).flatMap { URL(string: $0.uri) }
    }

    /// The profile as plain text. References by ID ("[a123456]") become the names of this artist's members,
    /// groups and aliases, which Discogs sends alongside; without them a bio read "a duo made up of  & ".
    var plainProfile: String? {
        guard let profile else { return nil }
        var names: [Int: String] = [id: name]
        for reference in (members ?? []) + (groups ?? []) + (aliases ?? []) { names[reference.id] = reference.name }
        return DiscogsMarkup.plainText(profile, names: names)
    }
}

/// What the inspector shows: Discogs' answer plus the photo saved on this Mac.
struct ArtistInfo: Equatable, Sendable {
    var artist: DiscogsArtist
    var photo: URL?
}

/// An answer saved on disk. "Not found" is saved too, and asked again after 30 days. `chosenID` records
/// a match the user picked with "Wrong artist?", which is kept even when it isn't the search's best guess.
struct CachedArtistInfo: Codable, Equatable, Sendable {
    var artist: DiscogsArtist?
    var fetchedAt: Date
    var chosenID: Int?

    func isFresh(now: Date) -> Bool {
        artist != nil || now.timeIntervalSince(fetchedAt) < 30 * 86_400
    }
}

/// Picks the Discogs search result that is this artist. Only exact names count (ignoring case, accents
/// and Discogs' " (2)" disambiguation suffix): a wrong artist is worse than none, and the user can still
/// pick one by hand.
enum ArtistMatcher {
    static func baseName(_ discogsName: String) -> String {
        discogsName.replacing(#/\s\(\d+\)$/#, with: "")
    }

    static func best(_ results: [DiscogsSearchResult], name: String) -> DiscogsSearchResult? {
        let target = SearchText.fold(name).trimmingCharacters(in: .whitespaces)
        return results.first { SearchText.fold(baseName($0.title)) == target }
    }
}

/// Discogs profiles use BBCode-like tags. Plain text keeps the names and link titles and drops the rest.
enum DiscogsMarkup {
    /// `names` resolves artist references by ID (`[a123]`), from the artist's own members, groups and aliases.
    static func plainText(_ profile: String, names: [Int: String] = [:]) -> String {
        var text = profile
        // Artist references by ID: their name when known.
        text = text.replacing(#/\[a=?(\d+)\]/#) { match in
            Int(match.1).flatMap { names[$0] }.map(ArtistMatcher.baseName) ?? ""
        }
        // Named references keep their name: [a=Artist], [l=Label].
        text = text.replacing(#/\[(?:a|l)=([^\]]+)\]/#) { ArtistMatcher.baseName(String($0.1)) }
        // Links keep their title: [url=https://…]Title[/url].
        text = text.replacing(#/\[url=[^\]]*\](.*?)\[/url\]/#) { String($0.1) }
        // Other references by number (labels, releases, masters: no name to show) and styling tags disappear.
        text = text.replacing(#/\[(?:l|r|m)=?\d+\]/#, with: "")
        text = text.replacing(#/\[/?(?:b|i|u|url)\]/#, with: "")
        text = text.replacing(#/[ \t]{2,}/#, with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
