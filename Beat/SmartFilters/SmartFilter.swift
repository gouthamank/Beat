import Foundation

/// A smart filter: an ordered pipeline of steps over the whole library, and what to show the result as.
struct SmartFilter: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// What the result is presented as. Sort and limit steps operate at this level
    /// (e.g. albums sorted by total plays), filters always test individual tracks.
    var output: ResultKind = .albums
    var steps: [FilterStep] = []
}

enum ResultKind: String, Codable, CaseIterable, Sendable {
    case songs, albums, artists, genres

    var title: String { rawValue.capitalized }
}

/// Steps run in order, so "sort, then limit" and "limit, then sort" give different results.
enum FilterStep: Codable, Hashable, Sendable {
    case filter(RuleGroup)
    case sort([SortKey])
    case limit(Limit)
}

struct RuleGroup: Codable, Hashable, Sendable {
    var match: Match = .all
    var nodes: [RuleNode] = []
}

enum Match: String, Codable, CaseIterable, Sendable {
    case all, any, none
}

indirect enum RuleNode: Codable, Hashable, Sendable {
    case rule(Rule)
    case group(RuleGroup)
}

struct Rule: Codable, Hashable, Sendable {
    var field: Field
    var op: RuleOperator
    var value: RuleValue
}

struct SortKey: Codable, Hashable, Sendable {
    var field: SortField
    var ascending: Bool
}

enum SortField: Codable, Hashable, Sendable {
    case field(Field)
    /// Shuffled with a seed that changes daily, so a "Random Albums" shelf is stable within a day.
    case random
    /// A value extracted from a text tag (see `CustomField`); the definition travels with the key.
    case custom(CustomField)
}

struct Limit: Codable, Hashable, Sendable {
    var count: Int
    var unit: LimitUnit
}

enum LimitUnit: String, Codable, CaseIterable, Sendable {
    case songs, albums, artists, genres, minutes, hours
}
