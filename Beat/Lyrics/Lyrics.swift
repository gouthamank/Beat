import Foundation

struct LyricLine: Hashable, Sendable {
    var time: TimeInterval
    /// Empty for an instrumental break.
    var text: String
}

enum Lyrics: Equatable, Sendable {
    case synced([LyricLine])
    case plain(String)
    case instrumental
    /// Nothing found; named so it never reads as `Optional.none`.
    case missing
}

/// Parses LRC ("[01:23.45] words") and finds the line playing at a given time.
enum LRC {
    /// Nil unless at least two timed lines are found, so plain lyrics never count as synced.
    static func parse(_ text: String) -> [LyricLine]? {
        var offset: TimeInterval = 0
        var tagged: [(tags: [Substring], words: String)] = []
        for raw in text.components(separatedBy: .newlines) {
            var rest = droppingListNumber(Substring(raw.trimmingCharacters(in: .whitespaces)))
            var tags: [Substring] = []
            // A line can carry several timestamps (a repeated chorus) and metadata tags.
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if tag.lowercased().hasPrefix("offset:"),
                   let ms = Double(tag.dropFirst("offset:".count).trimmingCharacters(in: .whitespaces)) {
                    offset = ms / 1000
                } else {
                    tags.append(tag)
                }
                rest = rest[rest.index(after: close)...]
            }
            tagged.append((tags, rest.trimmingCharacters(in: .whitespaces)))
        }
        let hours = colonTagsMeanHours(tagged.flatMap(\.tags))
        let lines = tagged.flatMap { line in
            line.tags.compactMap { timestamp($0, hours: hours) }.map { LyricLine(time: $0, text: line.words) }
        }
        guard lines.count >= 2 else { return nil }
        // A positive offset shows lyrics sooner. Ties keep file order.
        return lines.enumerated()
            .map { (index: $0.offset, line: LyricLine(time: max(0, $0.element.time - offset), text: $0.element.text)) }
            .sorted { ($0.line.time, $0.index) < ($1.line.time, $1.index) }
            .map(\.line)
    }

    /// Numbered tracklists ("12. [40:09] Artist - Title") put the number before the timestamp.
    /// Only dropped when a tag follows, so a plain lyric starting "1." is left alone.
    static func droppingListNumber(_ line: Substring) -> Substring {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return line }
        var rest = line.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")" else { return line }
        rest = rest.dropFirst().drop(while: \.isWhitespace)
        return rest.hasPrefix("[") ? rest : line
    }

    /// "a:bb:cc" is minutes:seconds:centiseconds in song LRC but hours:minutes:seconds in DJ mix
    /// tracklists. Centiseconds run to 99, so a file reads as hours only when none of its "a:bb:cc"
    /// tags has a last field of 60 or more; in a real song's dozens of lines one always does.
    static func colonTagsMeanHours(_ tags: [Substring]) -> Bool {
        let colonTags = tags.map { $0.split(separator: ":", omittingEmptySubsequences: false) }
            .filter { $0.count == 3 && $0.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) } }
        return !colonTags.isEmpty && colonTags.allSatisfy { parts in
            parts[1...].allSatisfy { $0.count == 2 && Int($0)! < 60 }
        }
    }

    /// "mm:ss", "mm:ss.xx", "mm:ss.xxx", "h:mm:ss.xx", and "mm:ss:xx" or, with `hours`, "h:mm:ss".
    /// Nil for metadata tags like "ar:Artist".
    static func timestamp(_ tag: Substring, hours: Bool = false) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              !parts[0].isEmpty, parts[0].allSatisfy(\.isNumber), let first = Double(parts[0]) else { return nil }
        if parts.count == 3 {
            guard !parts[1].isEmpty, parts[1].allSatisfy(\.isNumber), let middle = Double(parts[1]),
                  !parts[2].isEmpty, parts[2].allSatisfy({ $0.isNumber || $0 == "." }), let last = Double(parts[2])
            else { return nil }
            // A decimal point means the last field is seconds, so the first must be hours.
            if hours || parts[2].contains(".") { return first * 3600 + middle * 60 + last }
            guard parts[2].allSatisfy(\.isNumber) else { return nil }
            return first * 60 + middle + last / pow(10, Double(parts[2].count))
        }
        guard !parts[1].isEmpty, parts[1].allSatisfy({ $0.isNumber || $0 == "." }), let seconds = Double(parts[1]) else { return nil }
        return first * 60 + seconds
    }

    /// The last line starting at or before `time`; nil before the first line.
    static func currentIndex(in lines: [LyricLine], at time: TimeInterval) -> Int? {
        var low = 0, high = lines.count
        while low < high {
            let mid = (low + high) / 2
            if lines[mid].time <= time { low = mid + 1 } else { high = mid }
        }
        return low == 0 ? nil : low - 1
    }
}

/// A track in a DJ mix, from a tracklist stored as timed lyrics.
struct MixChapter: Hashable, Sendable {
    var start: TimeInterval
    var title: String
}

/// Tells a mix's tracklist from a song's lyrics: both parse to timed lines, but a tracklist's lines are
/// minutes apart and read like "Artist - Title". Both have to hold, so a sparse lyric can't pass by spacing alone.
enum MixChapters {
    static let minimumMedianGap: TimeInterval = 60
    static let minimumListingShare = 0.6

    /// Nil unless `lines` look like a tracklist.
    static func from(_ lines: [LyricLine]) -> [MixChapter]? {
        let timed = lines.filter { !$0.text.isEmpty }.sorted { $0.time < $1.time }
        guard timed.count >= 3 else { return nil }
        let gaps = zip(timed.dropFirst(), timed).map { $0.time - $1.time }.sorted()
        // Lyrics stay seconds apart even in long songs with sparse verses: the median skips the long breaks.
        guard gaps[gaps.count / 2] >= minimumMedianGap else { return nil }
        let listings = timed.filter { isListing($0.text) }.count
        guard Double(listings) >= Double(timed.count) * minimumListingShare else { return nil }
        return timed.map { MixChapter(start: $0.time, title: $0.text) }
    }

    /// "Artist - Title", with any dash, or "?" for an unknown track.
    static func isListing(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespaces)
        return text == "?" || [" - ", " – ", " — "].contains { text.contains($0) }
    }

    /// The chapter playing at `time`; nil before the first.
    static func chapter(at time: TimeInterval, in chapters: [MixChapter]) -> MixChapter? {
        chapters.last { $0.start <= time }
    }
}

/// Picks lyrics from the available sources. Synced beats plain; local beats online.
enum LyricsResolver {
    /// What LRCLIB returned for a song.
    struct Online: Codable, Equatable, Sendable {
        var synced: String?
        var plain: String?
        var instrumental = false
    }

    static func resolve(sidecar: String?, embedded: String?, online: Online?) -> Lyrics {
        for text in [sidecar, embedded, online?.synced] {
            if let text, let lines = LRC.parse(text) { return .synced(lines) }
        }
        for text in [embedded, online?.plain] {
            if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return .plain(text) }
        }
        return online?.instrumental == true ? .instrumental : .missing
    }

    /// LRCLIB's answer from `/api/get` (one record) or `/api/search` (a list of them).
    struct Record: Decodable, Equatable, Sendable {
        var duration: Double?
        var syncedLyrics: String?
        var plainLyrics: String?
        var instrumental: Bool?

        var online: Online {
            Online(synced: syncedLyrics, plain: plainLyrics, instrumental: instrumental ?? false)
        }
    }

    /// Search matches on artist and title only, so length is what tells the right recording from a
    /// live or extended one. Within that, synced beats plain beats instrumental, then the closest length.
    static func bestMatch(_ records: [Record], duration: TimeInterval) -> Online? {
        func rank(_ record: Record) -> Int {
            if record.syncedLyrics.flatMap(LRC.parse) != nil { return 0 }
            if record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false { return 1 }
            return record.instrumental == true ? 2 : 3
        }
        return records
            .compactMap { record -> (record: Record, rank: Int, gap: Double)? in
                guard let length = record.duration, abs(length - duration) <= 2 else { return nil }
                let rank = rank(record)
                return rank < 3 ? (record, rank, abs(length - duration)) : nil
            }
            .min { ($0.rank, $0.gap) < ($1.rank, $1.gap) }?
            .record.online
    }

    /// Online lookup only helps when the files have no synced lyrics.
    static func wantsOnline(sidecar: String?, embedded: String?) -> Bool {
        !([sidecar, embedded].contains { $0.flatMap(LRC.parse) != nil })
    }
}

/// An online answer saved on disk. "Not found" is saved too, and retried after 30 days.
struct CachedLyrics: Codable, Equatable, Sendable {
    var result: LyricsResolver.Online?
    var fetchedAt: Date

    func isFresh(now: Date) -> Bool {
        result != nil || now.timeIntervalSince(fetchedAt) < 30 * 86_400
    }
}
