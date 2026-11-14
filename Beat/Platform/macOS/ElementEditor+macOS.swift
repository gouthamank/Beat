import SwiftUI

/// The element editor's window on the Mac: the name across the top, the live preview beside a Rules / Appearance
/// panel (draggable split), and Delete, Cancel and Save along the bottom. `FilterEditorSheet` owns the draft and
/// what saving does.
struct ElementEditorLayout<Preview: View>: View {
    private enum EditorTab { case rules, appearance }

    @Binding var draft: EditableFilter
    @Binding var appearance: ElementAppearance
    let context: ElementEditorContext
    @ViewBuilder let preview: () -> Preview
    let save: () -> Void
    let cancel: () -> Void
    let delete: () -> Void
    @State private var tab = EditorTab.rules
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            nameBar
            Divider()
            HSplitView {
                preview()
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                settingsPanel
                    .frame(minWidth: 420, idealWidth: 460, maxWidth: 640, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 1000, idealWidth: 1180, maxWidth: 1400, minHeight: 640, idealHeight: 780, maxHeight: 900)
    }

    // MARK: Name and panel

    private var nameBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            TextField("Name", text: $draft.name, prompt: Text("Name"))
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .autocorrectionDisabled()
                .accessibilityIdentifier("editor.name")
                .focused($nameFocused)
            if let caption = context.nameCaption {
                Text(caption)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var settingsPanel: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                Text("Rules").tag(EditorTab.rules)
                Text("Appearance").tag(EditorTab.appearance)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)
            .accessibilityIdentifier("editor.tab")
            .padding(.vertical, 10)
            Divider()
            switch tab {
            case .rules:
                ScrollView {
                    pipeline
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                }
            case .appearance:
                FilterAppearanceForm(draft: $draft, appearance: $appearance)
            }
        }
    }

    // MARK: Pipeline

    private var pipeline: some View {
        VStack(alignment: .leading, spacing: 14) {
            // What the filter finds; everything below narrows and orders it.
            HStack(spacing: 8) {
                Text("Find").foregroundStyle(.secondary)
                Picker("Show as", selection: $draft.output) {
                    ForEach(ResultKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("editor.find")
            }
            Divider()
            Text("Steps run top to bottom").font(.caption).foregroundStyle(.secondary)
            // By id, not position: see `Binding.element(_:)`.
            ForEach(draft.steps) { step in
                let id = step.id
                let index = draft.steps.firstIndex { $0.id == id } ?? 0
                if index > 0 { Divider() }
                StepCard(
                    step: $draft.steps.element(step), output: draft.output,
                    canMoveUp: index > 0, canMoveDown: index < draft.steps.count - 1,
                    move: { offset in move(id, by: offset) },
                    delete: { withAnimation(.snappy) { draft.steps.removeAll { $0.id == id } } }
                )
            }
            Menu {
                Button("Filter", systemImage: "line.3.horizontal.decrease") { add(.newFilter()) }
                Button("Sort", systemImage: "arrow.up.arrow.down") { add(.newSort()) }
                Button("Limit", systemImage: "number") { add(.newLimit()) }
            } label: {
                Label("Add Step", systemImage: "plus")
            }
            .menuStyle(.button)
            .fixedSize()
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

    // MARK: Footer

    private var footer: some View {
        HStack {
            if context.canDelete {
                Button("Delete Element…", role: .destructive, action: delete)
            }
            Spacer()
            if !context.canSave {
                Button("Name the element") { nameFocused = true }
                    .linkButtonStyle()
                    .font(.caption)
            }
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("editor.cancel")
            Button(context.saveTitle, action: save)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("editor.save")
                .beatGlassButtonStyle(prominent: true)
                .disabled(!context.canSave)
        }
        .padding(14)
    }
}

// MARK: Step card

private struct StepCard: View {
    @Binding var step: EditStep
    let output: ResultKind
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(Color.accentColor).frame(width: 18)
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Group {
                    Button { move(-1) } label: { Image(systemName: "chevron.up") }
                        .disabled(!canMoveUp).help("Move Up")
                    Button { move(1) } label: { Image(systemName: "chevron.down") }
                        .disabled(!canMoveDown).help("Move Down")
                    Button(action: delete) { Image(systemName: "trash") }
                        .help("Remove Step")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            content
                .padding(.leading, 14)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step.kind {
        case .filter:
            RuleGroupEditor(group: Binding(
                get: { if case .filter(let g) = step.kind { g } else { EditGroup() } },
                set: { step.kind = .filter($0) }
            ))
        case .sort:
            SortKeysEditor(keys: Binding(
                get: { if case .sort(let k) = step.kind { k } else { [] } },
                set: { step.kind = .sort($0) }
            ), output: output)
        case .limit:
            LimitEditor(limit: Binding(
                get: { if case .limit(let l) = step.kind { l } else { Limit(count: 25, unit: .songs) } },
                set: { step.kind = .limit($0) }
            ))
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
        case .sort: "Sort"
        case .limit: "Limit"
        }
    }

    private var subtitle: String {
        switch step.kind {
        case .filter: "keep songs that match"
        case .sort: "order the \(output.rawValue)"
        case .limit: "keep only the first few"
        }
    }
}
