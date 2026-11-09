import Foundation

/// Editor-side copy of a SmartFilter. Steps, groups and rules carry IDs so SwiftUI can
/// bind to, insert, reorder and delete them safely; converted back to a SmartFilter on save.
struct EditableFilter: Identifiable, Hashable {
    var id: UUID
    var name: String
    var output: ResultKind
    var steps: [EditStep]

    init(_ filter: SmartFilter) {
        id = filter.id
        name = filter.name
        output = filter.output
        steps = filter.steps.map(EditStep.init)
    }

    static func new() -> EditableFilter {
        let filter = SmartFilter(
            id: UUID(), name: "New Smart Filter",
            output: .songs,
            steps: [
                .filter(RuleGroup(nodes: [.rule(Rule.make(field: .artist))])),
                .sort([SortKey(field: .field(.dateAdded), ascending: false)]),
                .limit(Limit(count: 50, unit: .songs)),
            ]
        )
        return EditableFilter(filter)
    }

    /// A copy with a new identity, for "Duplicate".
    func duplicated() -> EditableFilter {
        var copy = EditableFilter(makeFilter())
        copy.id = UUID()
        copy.name = name + " Copy"
        return copy
    }

    func makeFilter() -> SmartFilter {
        SmartFilter(
            id: id, name: name.trimmingCharacters(in: .whitespaces),
            output: output, steps: steps.map(\.step)
        )
    }
}

struct EditStep: Identifiable, Hashable {
    enum Kind: Hashable {
        case filter(EditGroup)
        case sort([EditSortKey])
        case limit(Limit)
    }

    var id = UUID()
    var kind: Kind

    init(kind: Kind) { self.kind = kind }

    init(_ step: FilterStep) {
        switch step {
        case .filter(let g): kind = .filter(EditGroup(g))
        case .sort(let keys): kind = .sort(keys.map { EditSortKey(key: $0) })
        case .limit(let l): kind = .limit(l)
        }
    }

    var step: FilterStep {
        switch kind {
        case .filter(let g): .filter(g.group)
        case .sort(let keys): .sort(keys.map(\.key))
        case .limit(let l): .limit(l)
        }
    }

    static func newFilter() -> EditStep { EditStep(kind: .filter(EditGroup(match: .all, nodes: [EditNode(content: .rule(.make(field: .genre)))]))) }
    static func newSort() -> EditStep { EditStep(kind: .sort([EditSortKey(key: SortKey(field: .field(.playCount), ascending: false))])) }
    static func newLimit() -> EditStep { EditStep(kind: .limit(Limit(count: 25, unit: .songs))) }
}

struct EditGroup: Identifiable, Hashable {
    var id = UUID()
    var match: Match = .all
    var nodes: [EditNode] = []

    init(match: Match = .all, nodes: [EditNode] = []) {
        self.match = match
        self.nodes = nodes
    }

    init(_ group: RuleGroup) {
        match = group.match
        nodes = group.nodes.map(EditNode.init)
    }

    var group: RuleGroup { RuleGroup(match: match, nodes: nodes.map(\.node)) }
}

struct EditNode: Identifiable, Hashable {
    indirect enum Content: Hashable {
        case rule(Rule)
        case group(EditGroup)
    }

    var id = UUID()
    var content: Content

    init(content: Content) { self.content = content }

    init(_ node: RuleNode) {
        switch node {
        case .rule(let r): content = .rule(r)
        case .group(let g): content = .group(EditGroup(g))
        }
    }

    var node: RuleNode {
        switch content {
        case .rule(let r): .rule(r)
        case .group(let g): .group(g.group)
        }
    }

    /// A copy with fresh ids at every level, so it can sit beside the original in a `ForEach`.
    func duplicated() -> EditNode { EditNode(node) }
}

struct EditSortKey: Identifiable, Hashable {
    var id = UUID()
    var key: SortKey
}

// MARK: Rule defaults

extension Rule {
    /// A rule on `field` with a sensible starting operator and value. Text rules start as
    /// "contains" with an empty value, which matches everything until the user types.
    static func make(field: Field) -> Rule {
        let op: RuleOperator = field.type == .text ? .contains : field.type.operators[0]
        return Rule(field: field, op: op, value: .defaultValue(for: field, op: op))
    }
}

extension RuleValue {
    static func defaultValue(for field: Field, op: RuleOperator) -> RuleValue {
        switch field.type {
        case .text: .text("")
        case .number:
            if op == .inRange { .range(field == .year ? 1990 : 0, field == .year ? 1999 : 10) }
            else { .number(field == .rating ? 4 : (field == .year ? 2000 : 0)) }
        case .date: (op == .inLast || op == .notInLast) ? .relative(30, .days) : .date(.now)
        case .bool: .none
        }
    }

    /// Whether this value has the shape `op` expects (e.g. a range for "is in the range").
    func fits(_ op: RuleOperator, field: Field) -> Bool {
        switch (field.type, self) {
        case (.text, .text): true
        case (.number, .range): op == .inRange
        case (.number, .number): op != .inRange
        case (.date, .relative): op == .inLast || op == .notInLast
        case (.date, .date): op == .before || op == .after
        case (.bool, _): true
        default: false
        }
    }
}
