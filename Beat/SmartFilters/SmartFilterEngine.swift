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

    init(snapshot: LibrarySnapshot, history: [PersistentID: PlayHistoryStore.Stats] = [:], now: Date = .now, calendar: Calendar = .current) {
        self.snapshot = snapshot
        self.now = now
        self.calendar = calendar
        tracks = history.isEmpty ? snapshot.tracks : snapshot.tracks.map { PreparedLibrary.merge($0, history[$0.id]) }
    }

    /// Only `tracks` (e.g. one artist's), merged with history: cheap enough to build on the main actor.
    init(snapshot: LibrarySnapshot, tracks: [Track], history: [PersistentID: PlayHistoryStore.Stats] = [:],
         now: Date = .now, calendar: Calendar = .current) {
        self.snapshot = snapshot
        self.now = now
        self.calendar = calendar
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

enum SmartFilterEngine {
    static func evaluate(_ filter: SmartFilter, in library: PreparedLibrary) -> FilterResult {
        var tracks = library.tracks

        var rng = SeededRNG(seed: seed(for: filter, now: library.now, calendar: library.calendar))
        for step in filter.steps {
            switch step {
            case .filter(let group):
                tracks = tracks.filter { matches(group, $0, library) }
            case .sort(let keys):
                tracks = sort(tracks, by: keys, groupedAs: filter.output, library: library, rng: &rng)
            case .limit(let limit):
                tracks = apply(limit, to: tracks, library: library)
            }
        }
        return project(tracks, as: filter.output, library: library)
    }

    // MARK: Rules

    static func matches(_ group: RuleGroup, _ track: Track, _ library: PreparedLibrary) -> Bool {
        guard !group.nodes.isEmpty else { return true }
        let test: (RuleNode) -> Bool = { node in
            switch node {
            case .rule(let rule): matches(rule, track, library)
            case .group(let inner): matches(inner, track, library)
            }
        }
        switch group.match {
        case .all: return group.nodes.allSatisfy(test)
        case .any: return group.nodes.contains(where: test)
        case .none: return !group.nodes.contains(where: test)
        }
    }

    static func matches(_ rule: Rule, _ track: Track, _ library: PreparedLibrary) -> Bool {
        switch rule.field.type {
        case .text:
            return matchText(text(rule.field, track), rule.op, rule.value)
        case .number:
            return matchNumber(number(rule.field, track), rule.op, rule.value)
        case .date:
            return matchDate(date(rule.field, track), rule.op, rule.value, library)
        case .bool:
            let value = bool(rule.field, track)
            return rule.op == .isFalse ? !value : value
        }
    }

    private static let textOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    private static func matchText(_ value: String, _ op: RuleOperator, _ ruleValue: RuleValue) -> Bool {
        guard case .text(let needle) = ruleValue else { return true }
        switch op {
        case .is: return value.compare(needle, options: textOptions) == .orderedSame
        case .isNot: return value.compare(needle, options: textOptions) != .orderedSame
        case .contains: return needle.isEmpty || value.range(of: needle, options: textOptions) != nil
        case .doesNotContain: return needle.isEmpty || value.range(of: needle, options: textOptions) == nil
        case .beginsWith: return value.range(of: needle, options: textOptions.union(.anchored)) != nil
        case .endsWith: return value.range(of: needle, options: textOptions.union([.anchored, .backwards])) != nil
        default: return true
        }
    }

    private static func matchNumber(_ value: Double, _ op: RuleOperator, _ ruleValue: RuleValue) -> Bool {
        switch (op, ruleValue) {
        case (.is, .number(let n)): return value == n
        case (.isNot, .number(let n)): return value != n
        case (.greaterThan, .number(let n)): return value > n
        case (.lessThan, .number(let n)): return value < n
        case (.inRange, .range(let lo, let hi)): return value >= min(lo, hi) && value <= max(lo, hi)
        default: return true
        }
    }

    /// A missing date (e.g. never played) is never "in the last N", and is always "not in the last N".
    private static func matchDate(_ value: Date?, _ op: RuleOperator, _ ruleValue: RuleValue, _ library: PreparedLibrary) -> Bool {
        switch (op, ruleValue) {
        case (.inLast, .relative(let n, let unit)), (.notInLast, .relative(let n, let unit)):
            let cutoff = library.calendar.date(byAdding: unit.component, value: -n, to: library.now) ?? library.now
            let isWithin = value.map { $0 >= cutoff } ?? false
            return op == .inLast ? isWithin : !isWithin
        case (.before, .date(let d)):
            return value.map { $0 < library.calendar.startOfDay(for: d) } ?? false
        case (.after, .date(let d)):
            guard let endOfDay = library.calendar.date(byAdding: .day, value: 1, to: library.calendar.startOfDay(for: d)) else { return false }
            return value.map { $0 >= endOfDay } ?? false
        default:
            return true
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
        let groups: [ArraySlice<Track>]
        if let key = groupKey(for: kind, library) {
            groups = group(tracks, by: key)
        } else {
            groups = tracks.indices.map { tracks[$0...$0] }
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

    private static func groupKey(for kind: ResultKind, _ library: PreparedLibrary) -> ((Track) -> String)? {
        switch kind {
        case .songs: nil
        case .albums: { String($0.albumID) }
        case .artists: { library.snapshot.artistKey($0) }
        case .genres: { $0.genre.lowercased() }
        }
    }

    /// Groups tracks by key, ordered by each group's first appearance.
    private static func group(_ tracks: [Track], by key: (Track) -> String) -> [ArraySlice<Track>] {
        var order: [String] = []
        var buckets: [String: [Track]] = [:]
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
