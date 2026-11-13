import SwiftUI

extension Binding {
    /// A binding to the element with `id`, found by id on every read and write. `ForEach($array)` bindings
    /// reach elements by position: a deleted rule still animating out could write back (a field losing
    /// focus) to a position that no longer existed, and the app trapped. Writes to a removed element are
    /// dropped; reads fall back to the element as it was.
    func element<Element: Identifiable & Sendable>(_ element: Element) -> Binding<Element>
        where Value == [Element], Element.ID: Sendable {
        let id = element.id
        return Binding<Element>(
            get: { wrappedValue.first { $0.id == id } ?? element },
            set: { newValue in
                if let i = wrappedValue.firstIndex(where: { $0.id == id }) { wrappedValue[i] = newValue }
            }
        )
    }
}

// MARK: Rule groups

struct RuleGroupEditor: View {
    @Binding var group: EditGroup
    var depth = 0
    var onDelete: (() -> Void)?
    var onDuplicate: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(depth == 0 ? "Match" : "Match")
                Picker("Match", selection: $group.match) {
                    Text("all").tag(Match.all)
                    Text("any").tag(Match.any)
                    Text("none").tag(Match.none)
                }
                .labelsHidden()
                .fixedSize()
                Text("of the following rules:")
                Spacer()
                if let onDuplicate {
                    Button(action: onDuplicate) { Image(systemName: "plus.square.on.square") }
                        .buttonStyle(.borderless)
                        .help("Duplicate Group")
                }
                if let onDelete {
                    Button(action: onDelete) { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .help("Remove Group")
                }
            }
            .foregroundStyle(.secondary)

            ForEach(group.nodes) { node in
                let id = node.id
                RuleNodeEditor(node: $group.nodes.element(node), depth: depth,
                               onDelete: { withAnimation(.snappy) { group.nodes.removeAll { $0.id == id } } },
                               onDuplicate: { duplicate(id) })
            }

            HStack(spacing: 14) {
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
            .buttonStyle(.borderless)
            .font(.callout)
        }
    }

    /// Inserts a copy just below, so a similar rule only needs the parts that differ changed.
    private func duplicate(_ id: UUID) {
        guard let i = group.nodes.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(.snappy) { group.nodes.insert(group.nodes[i].duplicated(), at: i + 1) }
    }
}

private struct RuleNodeEditor: View {
    @Binding var node: EditNode
    let depth: Int
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    var body: some View {
        switch node.content {
        case .rule:
            RuleRow(rule: Binding(
                get: { if case .rule(let r) = node.content { r } else { .make(field: .title) } },
                set: { node.content = .rule($0) }
            ), onDelete: onDelete, onDuplicate: onDuplicate)
        case .group:
            // AnyView breaks the recursive opaque-type cycle (groups contain groups).
            AnyView(
                RuleGroupEditor(group: Binding(
                    get: { if case .group(let g) = node.content { g } else { EditGroup() } },
                    set: { node.content = .group($0) }
                ), depth: depth + 1, onDelete: onDelete, onDuplicate: onDuplicate)
                .padding(10)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .leading) {
                    Capsule().fill(Color.accentColor.opacity(0.6)).frame(width: 3).padding(.vertical, 8)
                }
            )
        }
    }
}

// MARK: A single rule

private struct RuleRow: View {
    @Binding var rule: Rule
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    /// A phone: the menus take their text's width. Two fixed 150 pt menus and the buttons were wider than the screen,
    /// and pushed the whole editor past both edges.
    @Environment(\.compactLayout) private var compact

    /// One line when the editor's panel is wide enough; otherwise the value moves under field and operator.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                fieldPicker
                operatorPicker
                RuleValueEditor(rule: $rule).frame(minWidth: 140, alignment: .leading)
                Spacer(minLength: 0)
                buttons
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    fieldPicker
                    operatorPicker
                    Spacer(minLength: 0)
                    buttons
                }
                RuleValueEditor(rule: $rule)
            }
        }
    }

    private var fieldPicker: some View {
        Picker("Field", selection: Binding(get: { rule.field }, set: { rule.setField($0) })) {
            RuleFieldChoices()
        }
        .labelsHidden()
        .frame(width: compact ? nil : 150)
    }

    private var operatorPicker: some View {
        Picker("Operator", selection: Binding(get: { rule.op }, set: { rule.setOperator($0) })) {
            ForEach(rule.field.type.operators, id: \.self) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .frame(width: compact ? nil : 150)
    }

    private var buttons: some View {
        HStack(spacing: 6) {
            Button(action: onDuplicate) { Image(systemName: "plus.square.on.square") }
                .help("Duplicate Rule")
            Button(action: onDelete) { Image(systemName: "minus.circle") }
                .help("Remove Rule")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

}

/// A rule's field menu, in sections. Shared by the Mac's rule rows and the phone's rule form.
struct RuleFieldChoices: View {
    var body: some View {
        section("Text", [.title, .artist, .albumArtist, .album, .composer, .genre, .grouping, .comments, .kind])
        section("Numbers", [.rating, .playCount, .skipCount, .year, .duration, .bpm, .bitrate, .sampleRate, .trackNumber, .discNumber])
        section("Dates", [.dateAdded, .lastPlayed, .lastSkipped, .dateModified])
        section("Other", [.compilation, .hasArtwork])
    }

    private func section(_ title: String, _ fields: [Field]) -> some View {
        Section(title) {
            ForEach(fields, id: \.self) { Text($0.title).tag($0) }
        }
    }
}

extension Rule {
    /// Another field, keeping the operator and value when they still make sense (same kind of field), else
    /// starting over with that field's defaults. Rating's stars don't carry over to other numbers.
    mutating func setField(_ field: Field) {
        if field.type == self.field.type, field != .rating, self.field != .rating {
            self.field = field
        } else {
            self = .make(field: field)
        }
    }

    /// Another operator, with a fresh value when the old one doesn't fit it (a range for "is in the range").
    mutating func setOperator(_ op: RuleOperator) {
        self.op = op
        if !value.fits(op, field: field) {
            value = .defaultValue(for: field, op: op)
        }
    }
}

struct RuleValueEditor: View {
    @Binding var rule: Rule

    var body: some View {
        switch (rule.field.type, rule.value) {
        case (.text, .text(let s)):
            TextField("Value", text: Binding(get: { s }, set: { rule.value = .text($0) }))
                #if os(macOS)
                .textFieldStyle(.roundedBorder)
                #endif
                .autocorrectionDisabled()
                #if os(macOS)
                .frame(minWidth: 120, maxWidth: 220)
                #else
                // Its own row in the rule's form: the whole row takes the tap, not just its first 220 points.
                .frame(maxWidth: .infinity, alignment: .leading)
                #endif
        case (.number, .number(let n)) where rule.field == .rating:
            StarPicker(stars: Binding(get: { Int(n) }, set: { rule.value = .number(Double($0)) }))
        case (.number, .number(let n)):
            NumberField(value: Binding(get: { n }, set: { rule.value = .number($0) }))
        case (.number, .range(let lo, let hi)):
            NumberField(value: Binding(get: { lo }, set: { rule.value = .range($0, hi) }))
            Text("to").foregroundStyle(.secondary)
            NumberField(value: Binding(get: { hi }, set: { rule.value = .range(lo, $0) }))
        case (.date, .relative(let n, let unit)):
            NumberField(value: Binding(get: { Double(n) }, set: { rule.value = .relative(max(Int($0), 0), unit) }))
            Picker("Unit", selection: Binding(get: { unit }, set: { rule.value = .relative(n, $0) })) {
                ForEach(DateUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        case (.date, .date(let d)):
            DatePicker("Date", selection: Binding(get: { d }, set: { rule.value = .date($0) }), displayedComponents: .date)
                .labelsHidden()
                #if os(macOS)
                .datePickerStyle(.field)
                #else
                .datePickerStyle(.compact)
                #endif
        default:
            EmptyView()
        }
    }
}

struct NumberField: View {
    @Binding var value: Double

    var body: some View {
        TextField("", value: $value, format: .number.grouping(.never))
            #if os(macOS)
            .textFieldStyle(.roundedBorder)
            #endif
            .multilineTextAlignment(.trailing)
            .frame(width: 72)
    }
}

struct StarPicker: View {
    @Binding var stars: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Button { stars = (stars == i ? i - 1 : i) } label: {
                    Image(systemName: i <= stars ? "star.fill" : "star")
                        .foregroundStyle(i <= stars ? Color.accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .help("\(stars) stars")
    }
}

// MARK: Sort and limit

struct SortKeysEditor: View {
    @Binding var keys: [EditSortKey]
    let output: ResultKind
    /// A phone: the field menu takes its text's width, as in `RuleRow`.
    @Environment(\.compactLayout) private var compact

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(keys) { key in
                let id = key.id
                let binding = $keys.element(key)
                let isFirst = keys.first?.id == id
                HStack(spacing: 8) {
                    Text(isFirst ? "Sort by" : "then by")
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .leading)
                    SortFieldPicker(title: "Field", selection: Binding(
                        get: { key.key.field },
                        set: { if let field = $0 { binding.wrappedValue.key.field = field } }
                    ))
                    .labelsHidden()
                    .frame(width: compact ? nil : 170)
                    if let labels = Self.orderLabels(key.key.field) {
                        Picker("Order", selection: binding.key.ascending) {
                            Text(labels.descending).tag(false)
                            Text(labels.ascending).tag(true)
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Spacer(minLength: 0)
                    if keys.count > 1 {
                        Button { withAnimation(.snappy) { keys.removeAll { $0.id == id } } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Button("Add Sort Key", systemImage: "plus.circle") {
                withAnimation(.snappy) { keys.append(EditSortKey(key: SortKey(field: .field(.title), ascending: true))) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
            if output != .songs {
                Text("\(output.title) are ranked by their combined value: total plays, average rating, latest date.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    static func orderLabels(_ field: Field) -> (ascending: String, descending: String) {
        switch field.type {
        case .text: ("A to Z", "Z to A")
        case .date: ("Oldest First", "Newest First")
        default: ("Lowest First", "Highest First")
        }
    }

    /// Direction labels for any sort; nil for Random, which has no direction.
    static func orderLabels(_ field: SortField) -> (ascending: String, descending: String)? {
        switch field {
        case .random: nil
        case .field(let f): orderLabels(f)
        case .custom: ("A to Z", "Z to A")
        }
    }
}

struct LimitEditor: View {
    @Binding var limit: Limit

    var body: some View {
        HStack(spacing: 8) {
            Text("Keep the first").foregroundStyle(.secondary)
            NumberField(value: Binding(get: { Double(limit.count) }, set: { limit.count = max(Int($0), 0) }))
            Picker("Unit", selection: $limit.unit) {
                ForEach(LimitUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 0)
        }
    }
}
