import Foundation

struct FilterResult: Sendable, Equatable {
    var kind: ResultKind
    /// Every track in the result, in result order. Used to play a whole section.
    var tracks: [Track]
    var albums: [Album] = []
    var artists: [Artist] = []
    var genres: [Genre] = []

    var count: Int {
        switch kind {
        case .songs: tracks.count
        case .albums: albums.count
        case .artists: artists.count
        case .genres: genres.count
        }
    }
}

/// The library with Beat's play history merged in, shared by every filter in one refresh.
struct PreparedLibrary: Sendable {
    let snapshot: LibrarySnapshot
    let tracks: [Track]
    let now: Date
    let calendar: Calendar
    /// Text fields folded for matching. Pass the previous one while the library itself is unchanged (plays only
    /// change counts), so it isn't folded again.
    let folded: FoldedText

    init(snapshot: LibrarySnapshot, history: [PersistentID: PlayHistoryStore.Stats] = [:], now: Date = .now, calendar: Calendar = .current,
         folded: FoldedText? = nil) {
        self.snapshot = snapshot
        self.now = now
        self.calendar = calendar
        self.folded = folded ?? FoldedText(tracks: snapshot.tracks)
        tracks = history.isEmpty ? snapshot.tracks : snapshot.tracks.map { PreparedLibrary.merge($0, history[$0.id]) }
    }

    /// Only `tracks` (e.g. one artist's), merged with history: cheap enough to build on the main actor.
    init(snapshot: LibrarySnapshot, tracks: [Track], history: [PersistentID: PlayHistoryStore.Stats] = [:],
         now: Date = .now, calendar: Calendar = .current) {
        self.snapshot = snapshot
        self.now = now
        self.calendar = calendar
        self.folded = FoldedText(tracks: tracks)
        self.tracks = tracks.map { PreparedLibrary.merge($0, history[$0.id]) }
    }

    private static func merge(_ track: Track, _ stats: PlayHistoryStore.Stats?) -> Track {
        guard let stats else { return track }
        var t = track
        t.playCount += stats.playCount
        t.skipCount += stats.skipCount
        t.lastPlayed = [t.lastPlayed, stats.lastPlayed].compactMap { $0 }.max()
        t.lastSkipped = [t.lastSkipped, stats.lastSkipped].compactMap { $0 }.max()
        return t
    }
}

/// Each text field of every song, folded (case and accents removed) the first time a rule reads that field, then
/// shared by every filter: folding with Foundation per song per rule was most of a filter's cost (about 85 ms a
/// pass over 20k songs). Thread-safe, as a page's elements are evaluated in parallel.
final class FoldedText: @unchecked Sendable {
    private let tracks: [Track]
    private let lock = NSLock()
    private var fields: [Field: [PersistentID: String]] = [:]

    init(tracks: [Track]) { self.tracks = tracks }

    func values(_ field: Field) -> [PersistentID: String] {
        if let done = lock.withLock({ fields[field] }) { return done }
        // Folded outside the lock, so other fields aren't held up; a rare duplicate fold is harmless.
        var values = [PersistentID: String](minimumCapacity: tracks.count)
        for track in tracks { values[track.id] = SearchText.fold(SmartFilterEngine.text(field, track)) }
        lock.withLock { fields[field] = values }
        return values
    }
}

enum SmartFilterEngine {
    static func evaluate(_ filter: SmartFilter, in library: PreparedLibrary) -> FilterResult {
        var tracks = library.tracks

        var rng = SeededRNG(seed: seed(for: filter, now: library.now, calendar: library.calendar))
        for step in filter.steps {
            switch step {
            case .filter(let group):
                let test = predicate(group, library)
                tracks = tracks.filter(test)
            case .sort(let keys):
                tracks = sort(tracks, by: keys, groupedAs: filter.output, library: library, rng: &rng)
            case .limit(let limit):
                tracks = apply(limit, to: tracks, library: library)
            }
        }
        return project(tracks, as: filter.output, library: library)
    }

    // MARK: Rules

    /// A group's rules turned into one test, built once per filter step: search text folded, field values looked
    /// up in the shared folded table, date cut-offs worked out, all before the first song is tried.
    static func predicate(_ group: RuleGroup, _ library: PreparedLibrary) -> @Sendable (Track) -> Bool {
        guard !group.nodes.isEmpty else { return { _ in true } }
        let tests = group.nodes.map { node -> @Sendable (Track) -> Bool in
            switch node {
            case .rule(let rule): predicate(rule, library)
            case .group(let inner): predicate(inner, library)
            }
        }
        switch group.match {
        case .all: return { track in tests.allSatisfy { $0(track) } }
        case .any: return { track in tests.contains { $0(track) } }
        case .none: return { track in !tests.contains { $0(track) } }
        }
    }

    static func matches(_ group: RuleGroup, _ track: Track, _ library: PreparedLibrary) -> Bool {
        predicate(group, library)(track)
    }

    static func predicate(_ rule: Rule, _ library: PreparedLibrary) -> @Sendable (Track) -> Bool {
        let field = rule.field
        switch field.type {
        case .text:
            guard case .text(let raw) = rule.value else { return { _ in true } }
            let needle = SearchText.fold(raw)
            let folded = library.folded.values(field)
            let value: @Sendable (Track) -> String = { folded[$0.id] ?? SearchText.fold(text(field, $0)) }
            // Empty search text: "contains" keeps everything, and "begins/ends with" matched nothing before
            // (Foundation finds no empty range); kept so.
            if needle.isEmpty, [RuleOperator.contains, .doesNotContain].contains(rule.op) { return { _ in true } }
            if needle.isEmpty, [RuleOperator.beginsWith, .endsWith].contains(rule.op) { return { _ in false } }
            switch rule.op {
            case .is: return { value($0) == needle }
            case .isNot: return { value($0) != needle }
            case .contains: return { utf8Contains(value($0), needle) }
            case .doesNotContain: return { !utf8Contains(value($0), needle) }
            case .beginsWith: return { value($0).hasPrefix(needle) }
            case .endsWith: return { value($0).hasSuffix(needle) }
            default: return { _ in true }
            }
        case .number:
            switch (rule.op, rule.value) {
            case (.is, .number(let n)): return { number(field, $0) == n }
            case (.isNot, .number(let n)): return { number(field, $0) != n }
            case (.greaterThan, .number(let n)): return { number(field, $0) > n }
            case (.lessThan, .number(let n)): return { number(field, $0) < n }
            case (.inRange, .range(let lo, let hi)):
                let low = min(lo, hi), high = max(lo, hi)
                return { (low...high).contains(number(field, $0)) }
            default: return { _ in true }
            }
        case .date:
            return datePredicate(field, rule.op, rule.value, library)
        case .bool:
            if rule.op == .isFalse { return { !bool(field, $0) } }
            return { bool(field, $0) }
        }
    }

    /// Byte search over two folded strings (both folded the same way, so comparing bytes is enough).
    static func utf8Contains(_ haystack: String, _ needle: String) -> Bool {
        var haystack = haystack, needle = needle
        return haystack.withUTF8 { h in
            needle.withUTF8 { n in
                n.isEmpty || (n.count <= h.count && memmem(h.baseAddress, h.count, n.baseAddress, n.count) != nil)
            }
        }
    }

    /// A missing date (e.g. never played) is never "in the last N", and is always "not in the last N".
    private static func datePredicate(_ field: Field, _ op: RuleOperator, _ ruleValue: RuleValue,
                                      _ library: PreparedLibrary) -> @Sendable (Track) -> Bool {
        let calendar = library.calendar
        switch (op, ruleValue) {
        case (.inLast, .relative(let n, let unit)), (.notInLast, .relative(let n, let unit)):
            let cutoff = calendar.date(byAdding: unit.component, value: -n, to: library.now) ?? library.now
            let inLast = op == .inLast
            return { track in
                let isWithin = date(field, track).map { $0 >= cutoff } ?? false
                return inLast ? isWithin : !isWithin
            }
        case (.before, .date(let d)):
            let start = calendar.startOfDay(for: d)
            return { date(field, $0).map { $0 < start } ?? false }
        case (.after, .date(let d)):
            guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: d)) else { return { _ in false } }
            return { date(field, $0).map { $0 >= endOfDay } ?? false }
        default:
            return { _ in true }
        }
    }

    // MARK: Field values

    static func text(_ field: Field, _ t: Track) -> String {
        switch field {
        case .title: t.title
        case .artist: t.displayArtist
        case .albumArtist: t.albumArtist
        case .album: t.album
        case .composer: t.composer
        case .genre: t.genre
        case .kind: t.kind
        case .comments: t.comments
        case .grouping: t.grouping
        default: ""
        }
    }

    static func number(_ field: Field, _ t: Track) -> Double {
        switch field {
        case .year: Double(t.year)
        case .rating: Double(t.stars)
        case .playCount: Double(t.playCount)
        case .skipCount: Double(t.skipCount)
        case .bpm: Double(t.bpm)
        case .bitrate: Double(t.bitrate)
        case .sampleRate: Double(t.sampleRate)
        case .duration: t.duration
        case .trackNumber: Double(t.trackNumber)
        case .discNumber: Double(t.discNumber)
        default: 0
        }
    }

    static func date(_ field: Field, _ t: Track) -> Date? {
        switch field {
        case .dateAdded: t.dateAdded
        case .dateModified: t.dateModified
        case .lastPlayed: t.lastPlayed
        case .lastSkipped: t.lastSkipped
        default: nil
        }
    }

    static func bool(_ field: Field, _ t: Track) -> Bool {
        switch field {
        case .compilation: t.isCompilation
        case .hasArtwork: t.hasArtwork
        default: false
        }
    }

    // MARK: Sorting

    private enum SortValue {
        case number(Double?)
        /// nil only for a custom field with no match.
        case text(String?)

        /// Missing values sort last in either direction.
        static func compare(_ a: SortValue, _ b: SortValue, ascending: Bool) -> ComparisonResult {
            switch (a, b) {
            case (.number(let x), .number(let y)):
                switch (x, y) {
                case (nil, nil): return .orderedSame
                case (nil, _): return .orderedDescending
                case (_, nil): return .orderedAscending
                case (let x?, let y?):
                    if x == y { return .orderedSame }
                    return (x < y) == ascending ? .orderedAscending : .orderedDescending
                }
            case (.text(let x), .text(let y)):
                switch (x, y) {
                case (nil, nil): return .orderedSame
                case (nil, _): return .orderedDescending
                case (_, nil): return .orderedAscending
                case (let x?, let y?):
                    let r = x.localizedStandardCompare(y)
                    if r == .orderedSame { return r }
                    return (r == .orderedAscending) == ascending ? .orderedAscending : .orderedDescending
                }
            default:
                return .orderedSame
            }
        }
    }

    private static func sortValue(_ field: Field, of tracks: ArraySlice<Track>) -> SortValue {
        switch field.type {
        case .text:
            return .text(tracks.first.map { text(field, $0) } ?? "")
        case .date:
            let dates = tracks.compactMap { date(field, $0)?.timeIntervalSinceReferenceDate }
            return .number(field.aggregate == .min ? dates.min() : dates.max())
        default:
            let values = tracks.map { number(field, $0) }
            guard !values.isEmpty else { return .number(nil) }
            switch field.aggregate {
            case .sum: return .number(values.reduce(0, +))
            case .average: return .number(values.reduce(0, +) / Double(values.count))
            case .min: return .number(values.min())
            case .max: return .number(values.max())
            }
        }
    }

    /// Albums in the order a smart filter would give them for `key`: each album's value aggregated over its
    /// tracks (plays summed, rating averaged, newest date…), ties kept in library order. Random is stable
    /// within a day.
    static func sort(_ albums: [Album], by key: SortKey, in library: PreparedLibrary) -> [Album] {
        let ids = Set(albums.map(\.id))
        let tracks = library.tracks.filter { ids.contains($0.albumID) }
        let day = UInt64(library.calendar.ordinality(of: .day, in: .era, for: library.now) ?? 0)
        var rng = SeededRNG(seed: day &* 0x9E37_79B9_7F4A_7C15)
        let byID = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<PersistentID>()
        return sort(tracks, by: [key], groupedAs: .albums, library: library, rng: &rng)
            .compactMap { seen.insert($0.albumID).inserted ? byID[$0.albumID] : nil }
    }

    /// Sorts tracks, or, for album/artist/genre results, sorts the groups by their aggregate value
    /// and keeps each group's tracks together in their existing order.
    private static func sort(_ tracks: [Track], by keys: [SortKey], groupedAs kind: ResultKind, library: PreparedLibrary, rng: inout SeededRNG) -> [Track] {
        guard !keys.isEmpty else { return tracks }
        let groups: [ArraySlice<Track>] = switch kind {
        case .songs: tracks.indices.map { tracks[$0...$0] }
        // By ID, not a string made from it for every song.
        case .albums: group(tracks) { $0.albumID }
        case .artists: group(tracks) { library.snapshot.artistKey($0) }
        case .genres: group(tracks) { $0.genre.lowercased() }
        }

        // Built once per key, so a custom field's pattern compiles once rather than per track.
        let extractors: [((Track) -> String?)?] = keys.map { key in
            if case .custom(let field) = key.field { field.extractor() } else { nil }
        }
        let values: [[SortValue]] = groups.map { members in
            keys.indices.map { k in
                switch keys[k].field {
                case .random: .number(Double(rng.next() >> 11))
                case .field(let field): sortValue(field, of: members)
                case .custom: .text(members.first.flatMap { extractors[k]?($0) })
                }
            }
        }

        let order = groups.indices.sorted { i, j in
            for (k, key) in keys.enumerated() {
                let r = SortValue.compare(values[i][k], values[j][k], ascending: key.ascending)
                if r != .orderedSame { return r == .orderedAscending }
            }
            return i < j // stable
        }
        return order.flatMap { groups[$0] }
    }

    /// Groups tracks by key, ordered by each group's first appearance.
    private static func group<Key: Hashable>(_ tracks: [Track], by key: (Track) -> Key) -> [ArraySlice<Track>] {
        var order: [Key] = []
        var buckets: [Key: [Track]] = [:]
        for t in tracks {
            let k = key(t)
            if buckets[k] == nil { order.append(k) }
            buckets[k, default: []].append(t)
        }
        return order.map { ArraySlice(buckets[$0]!) }
    }

    // MARK: Limits

    private static func apply(_ limit: Limit, to tracks: [Track], library: PreparedLibrary) -> [Track] {
        let count = max(limit.count, 0)
        switch limit.unit {
        case .songs:
            return Array(tracks.prefix(count))
        case .minutes, .hours:
            let budget = Double(count) * (limit.unit == .hours ? 3600 : 60)
            var total = 0.0
            var kept: [Track] = []
            for t in tracks {
                guard total + t.duration <= budget else { break }
                total += t.duration
                kept.append(t)
            }
            return kept
        case .albums, .artists, .genres:
            let key: (Track) -> String = switch limit.unit {
            case .albums: { String($0.albumID) }
            case .artists: { library.snapshot.artistKey($0) }
            default: { $0.genre.lowercased() }
            }
            var allowed = Set<String>()
            return tracks.filter { t in
                let k = key(t)
                if allowed.contains(k) { return true }
                guard allowed.count < count else { return false }
                allowed.insert(k)
                return true
            }
        }
    }

    // MARK: Projection

    private static func project(_ tracks: [Track], as kind: ResultKind, library: PreparedLibrary) -> FilterResult {
        var result = FilterResult(kind: kind, tracks: tracks)
        let snapshot = library.snapshot
        switch kind {
        case .songs:
            break
        case .albums:
            result.albums = unique(tracks.map(\.albumID)).compactMap { snapshot.albumsByID[$0] }
            // Play each album's tracks in disc/track order, albums in result order.
            let position = Dictionary(uniqueKeysWithValues: result.albums.enumerated().map { ($1.id, $0) })
            result.tracks = tracks.sorted {
                (position[$0.albumID] ?? 0, $0.discNumber, $0.trackNumber) < (position[$1.albumID] ?? 0, $1.discNumber, $1.trackNumber)
            }
        case .artists:
            result.artists = unique(tracks.map(snapshot.artistKey)).compactMap { snapshot.artistsByID[$0] }
        case .genres:
            result.genres = unique(tracks.map { $0.genre.lowercased() }).compactMap { snapshot.genresByID[$0] }
        }
        return result
    }

    private static func unique<T: Hashable>(_ values: [T]) -> [T] {
        var seen = Set<T>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func seed(for filter: SmartFilter, now: Date, calendar: Calendar) -> UInt64 {
        let day = UInt64(calendar.ordinality(of: .day, in: .era, for: now) ?? 0)
        let (hi, lo) = withUnsafeBytes(of: filter.id.uuid) { raw in
            (raw.loadUnaligned(fromByteOffset: 0, as: UInt64.self), raw.loadUnaligned(fromByteOffset: 8, as: UInt64.self))
        }
        return hi ^ lo ^ (day &* 0x9E37_79B9_7F4A_7C15)
    }
}

/// Deterministic SplitMix64 generator.
struct SeededRNG: RandomNumberGenerator, Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
