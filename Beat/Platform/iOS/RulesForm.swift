import SwiftUI

/// An element's rules on iPad and iPhone in the Settings idiom: each step a grouped section, each rule one line
/// ("Artist contains “Akon”") that opens its own form. The Mac's sentence rows packed a phone screen with menus.
struct RulesForm: View {
    @Binding var draft: EditableFilter
    let nameCaption: String?
    /// Deletes the element (after asking); nil for a new element or the defaults.
    let delete: (() -> Void)?

    var body: some View {
        Form {
            // The name first: it scrolls with the rest rather than taking a fixed bar.
            Section {
                TextField("Name", text: $draft.name, prompt: Text("Name"))
                    .font(.headline)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("editor.name")
            } footer: {
                if let nameCaption { Text(nameCaption) }
            }
            Section {
                Picker("Find", selection: $draft.output) {
                    ForEach(ResultKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } footer: {
                Text("Steps run top to bottom.")
            }
            // By id, not position: see `Binding.element(_:)`.
            ForEach(draft.steps) { step in
                let id = step.id
                let index = draft.steps.firstIndex { $0.id == id } ?? 0
                StepSection(
                    step: $draft.steps.element(step), output: draft.output,
                    canMoveUp: index > 0, canMoveDown: index < draft.steps.count - 1,
                    move: { move(id, by: $0) },
                    delete: { withAnimation(.snappy) { draft.steps.removeAll { $0.id == id } } }
                )
            }
            Section {
                Menu {
                    Button("Filter", systemImage: "line.3.horizontal.decrease") { add(.newFilter()) }
                    Button("Sort", systemImage: "arrow.up.arrow.down") { add(.newSort()) }
                    Button("Limit", systemImage: "number") { add(.newLimit()) }
                } label: {
                    Label("Add Step", systemImage: "plus")
                }
            }
            if let delete {
                Section {
                    Button("Delete Element", role: .destructive, action: delete)
                }
            }
        }
    }

    private func add(_ step: EditStep) {
        withAnimation(.snappy) { draft.steps.append(step) }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let i = draft.steps.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard draft.steps.indices.contains(j) else { return }
        withAnimation(.snappy) { draft.steps.swapAt(i, j) }
    }
}

/// One step as a section: its name and a menu (move, remove) in the header, its settings as rows.
private struct StepSection: View {
    @Binding var step: EditStep
    let output: ResultKind
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let delete: () -> Void

    var body: some View {
        Section {
            switch step.kind {
            case .filter:
                FormRuleGroup(group: Binding(
                    get: { if case .filter(let g) = step.kind { g } else { EditGroup() } },
                    set: { step.kind = .filter($0) }
                ))
            case .sort:
                FormSortKeys(keys: Binding(
                    get: { if case .sort(let k) = step.kind { k } else { [] } },
                    set: { step.kind = .sort($0) }
                ))
            case .limit:
                FormLimit(limit: Binding(
                    get: { if case .limit(let l) = step.kind { l } else { Limit(count: 25, unit: .songs) } },
                    set: { step.kind = .limit($0) }
                ))
            }
        } header: {
            HStack {
                Label(title, systemImage: symbol)
                Spacer()
                Menu {
                    Button("Move Up", systemImage: "chevron.up") { move(-1) }.disabled(!canMoveUp)
                    Button("Move Down", systemImage: "chevron.down") { move(1) }.disabled(!canMoveDown)
                    Divider()
                    Button("Remove Step", systemImage: "trash", role: .destructive, action: delete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Step Options")
            }
        }
    }

    private var symbol: String {
        switch step.kind {
        case .filter: "line.3.horizontal.decrease"
        case .sort: "arrow.up.arrow.down"
        case .limit: "number"
        }
    }

    private var title: String {
        switch step.kind {
        case .filter: "Filter"
        case .sort: "Sort \(output.rawValue)"
        case .limit: "Limit"
        }
    }
}

/// A rule group's rows: how its rules combine, a line per rule or nested group, and buttons to add more.
private struct FormRuleGroup: View {
    @Binding var group: EditGroup
    var depth = 0

    var body: some View {
        Picker("Match", selection: $group.match) {
            Text("All rules").tag(Match.all)
            Text("Any rule").tag(Match.any)
            Text("No rules").tag(Match.none)
        }
        ForEach(group.nodes) { node in
            let id = node.id
            let binding = $group.nodes.element(node)
            row(node, binding: binding)
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        withAnimation(.snappy) { group.nodes.removeAll { $0.id == id } }
                    }
                    Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(id) }
                }
        }
        Button("Add Rule", systemImage: "plus.circle") {
            withAnimation(.snappy) { group.nodes.append(EditNode(content: .rule(.make(field: .artist)))) }
        }
        if depth < 3 {
            Button("Add Group", systemImage: "plus.square.on.square") {
                let inner = EditGroup(match: .any, nodes: [EditNode(content: .rule(.make(field: .genre)))])
                withAnimation(.snappy) { group.nodes.append(EditNode(content: .group(inner))) }
            }
        }
    }

    @ViewBuilder
    private func row(_ node: EditNode, binding: Binding<EditNode>) -> some View {
        switch node.content {
        case .rule(let rule):
            NavigationLink {
                RuleForm(rule: Binding(
                    get: { if case .rule(let r) = binding.wrappedValue.content { r } else { rule } },
                    set: { binding.wrappedValue.content = .rule($0) }
                ))
            } label: {
                Text(RuleSummary.text(rule)).lineLimit(2)
            }
        case .group(let inner):
            NavigationLink {
                Form {
                    // AnyView breaks the recursive opaque-type cycle (groups contain groups).
                    AnyView(FormRuleGroup(group: Binding(
                        get: { if case .group(let g) = binding.wrappedValue.content { g } else { inner } },
                        set: { binding.wrappedValue.content = .group($0) }
                    ), depth: depth + 1))
                }
                .navigationTitle("Group")
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(RuleSummary.groupTitle(inner))
                    Text(inner.nodes.count == 1 ? "1 rule" : "\(inner.nodes.count) rules")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func duplicate(_ id: UUID) {
        guard let i = group.nodes.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.snappy) { group.nodes.insert(group.nodes[i].duplicated(), at: i + 1) }
    }
}

/// One rule, opened from its line: field, condition and value as rows.
private struct RuleForm: View {
    @Binding var rule: Rule

    var body: some View {
        Form {
            Section {
                Picker("Field", selection: Binding(get: { rule.field }, set: { rule.setField($0) })) {
                    RuleFieldChoices()
                }
                Picker("Condition", selection: Binding(get: { rule.op }, set: { rule.setOperator($0) })) {
                    ForEach(rule.field.type.operators, id: \.self) { Text($0.title).tag($0) }
                }
            }
            if rule.field.type != .bool {
                Section("Value") {
                    HStack(spacing: 8) { RuleValueEditor(rule: $rule) }
                }
            }
        }
        .navigationTitle(rule.field.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Sort keys as one line each ("Date Added, newest first"), opening a form to change them.
private struct FormSortKeys: View {
    @Binding var keys: [EditSortKey]

    var body: some View {
        ForEach(keys) { key in
            let id = key.id
            let binding = $keys.element(key)
            NavigationLink {
                Form {
                    SortFieldPicker(title: "Field", selection: Binding(
                        get: { key.key.field },
                        set: { if let field = $0 { binding.wrappedValue.key.field = field } }
                    ))
                    if let labels = SortKeysEditor.orderLabels(binding.wrappedValue.key.field) {
                        Picker("Order", selection: binding.key.ascending) {
                            Text(labels.descending).tag(false)
                            Text(labels.ascending).tag(true)
                        }
                    }
                }
                .navigationTitle("Sort")
                .navigationBarTitleDisplayMode(.inline)
            } label: {
                LabeledContent(keys.first?.id == id ? "Sort by" : "Then by", value: RuleSummary.text(key.key))
            }
            .swipeActions {
                if keys.count > 1 {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        withAnimation(.snappy) { keys.removeAll { $0.id == id } }
                    }
                }
            }
        }
        Button("Add Sort Key", systemImage: "plus.circle") {
            withAnimation(.snappy) { keys.append(EditSortKey(key: SortKey(field: .field(.title), ascending: true))) }
        }
    }
}

/// How many to keep, and of what.
private struct FormLimit: View {
    @Binding var limit: Limit

    var body: some View {
        LabeledContent("Keep the first") {
            TextField("Count", value: Binding(get: { limit.count }, set: { limit.count = max($0, 0) }), format: .number.grouping(.never))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
        }
        Picker("Of", selection: $limit.unit) {
            ForEach(LimitUnit.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }
    }
}

/// One-line descriptions for the rows that open a rule or sort key.
@MainActor
enum RuleSummary {
    static func text(_ rule: Rule) -> String {
        let value = valueText(rule)
        return value.isEmpty ? "\(rule.field.title) \(rule.op.title)" : "\(rule.field.title) \(rule.op.title) \(value)"
    }

    static func groupTitle(_ group: EditGroup) -> String {
        switch group.match {
        case .all: "Group: all of"
        case .any: "Group: any of"
        case .none: "Group: none of"
        }
    }

    static func text(_ key: SortKey) -> String {
        let name: String = switch key.field {
        case .random: "Random"
        case .field(let field): field.title
        case .custom(let field): field.name
        }
        guard let labels = SortKeysEditor.orderLabels(key.field) else { return name }
        return "\(name), \((key.ascending ? labels.ascending : labels.descending).lowercased())"
    }

    private static func valueText(_ rule: Rule) -> String {
        switch rule.value {
        case .none: return ""
        case .text(let text): return text.isEmpty ? "…" : "“\(text)”"
        case .number(let n) where rule.field == .rating: return String(repeating: "★", count: Int(n))
        case .number(let n): return n.formatted(.number.grouping(.never))
        case .range(let lo, let hi): return "\(lo.formatted(.number.grouping(.never)))–\(hi.formatted(.number.grouping(.never)))"
        case .date(let date): return date.formatted(date: .abbreviated, time: .omitted)
        case .relative(let n, let unit): return "\(n) \(unit.rawValue)"
        }
    }
}
