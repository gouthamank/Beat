import SwiftUI

/// Creates or edits an element, or the defaults new elements start from. The live preview is the main
/// area; Rules and Appearance sit in a panel on the right, and the name at the top belongs to neither.
struct FilterEditorSheet: View {
    private enum EditorTab { case rules, appearance }

    private let target: EditorTarget
    @State private var draft: EditableFilter
    @State private var appearance: ElementAppearance
    @State private var preview: FilterResult?
    @State private var confirmDelete = false
    @State private var tab = EditorTab.rules
    @FocusState private var nameFocused: Bool
    /// The preview's elements need a page to belong to; defaults have none, so they get a stable stand-in.
    @State private var standInPageID = UUID()

    @Environment(PageStore.self) private var pages
    @Environment(LibraryStore.self) private var library
    @Environment(PlayHistoryStore.self) private var history
    @Environment(\.dismiss) private var dismiss

    init(draft: ElementDraft) {
        target = draft.target
        _draft = State(initialValue: draft.filter)
        _appearance = State(initialValue: draft.appearance)
    }

    private var pageID: UUID? {
        if case .page(let id) = target { id } else { nil }
    }
    private var isNew: Bool { pageID.map { pages.element(draft.id, on: $0) == nil } ?? false }
    private var element: PageElement { PageElement(filter: draft.makeFilter(), appearance: appearance) }
    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            nameBar
            Divider()
            HSplitView {
                ElementPreview(element: element, pageID: pageID ?? standInPageID, result: preview)
                    .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                settingsPanel
                    .frame(minWidth: 420, idealWidth: 460, maxWidth: 640, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(minWidth: 1000, idealWidth: 1180, maxWidth: 1400, minHeight: 640, idealHeight: 780, maxHeight: 900)
        .task(id: element) { await refreshPreview() }
        .environment(\.customFieldSamples, preview?.tracks ?? [])
        // Here rather than in the Appearance form, which isn't on screen while Show as changes on Rules.
        .onChange(of: draft.output) { _, output in appearance.fit(to: output) }
        // A custom field edited from inside the editor updates every element, and this unsaved draft too.
        .onChange(of: pages.customFields) { _, fields in
            draft.refreshCustomFields(fields)
            appearance.sortOverride = appearance.sortOverride?.refreshed(fields)
        }
        .confirmationDialog("Delete “\(draft.name)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let pageID { pages.deleteElement(draft.id, from: pageID) }
                dismiss()
            }
        } message: {
            Text("Its smart filter is deleted with it.")
        }
    }

    // MARK: Name and panel

    private var nameBar: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            TextField("Name", text: $draft.name, prompt: Text("Name"))
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .focused($nameFocused)
            if target == .defaults {
                Text("Defaults for new elements")
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
            if pageID != nil, !isNew {
                Button("Delete Element…", role: .destructive) { confirmDelete = true }
            }
            Spacer()
            if !canSave {
                Button("Name the element") { nameFocused = true }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(saveTitle) { save() }
                .keyboardShortcut(.defaultAction)
                .beatGlassButtonStyle(prominent: true)
                .disabled(!canSave)
        }
        .padding(14)
    }

    private var saveTitle: String {
        if pageID == nil { return "Save Defaults" }
        return isNew ? "Create" : "Save"
    }

    private func save() {
        switch target {
        case .page(let id): pages.saveElement(element, on: id)
        case .defaults: NewElementDefaults.save(element)
        }
        dismiss()
    }

    private func refreshPreview() async {
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        let filter = element.effectiveFilter
        let snapshot = library.snapshot
        let stats = history.stats
        let result = await Task.detached(priority: .userInitiated) {
            SmartFilterEngine.evaluate(filter, in: PreparedLibrary(snapshot: snapshot, history: stats))
        }.value
        guard !Task.isCancelled else { return }
        preview = result
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

// MARK: Preview

/// The element as it will look on its page, rules and appearance applied.
private struct ElementPreview: View {
    let element: PageElement
    let pageID: UUID
    let result: FilterResult?

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Preview").font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            Group {
                if let result {
                    if result.count == 0 {
                        ContentUnavailableView("No Matches", systemImage: "line.3.horizontal.decrease.circle",
                                               description: Text("Try loosening a rule or raising the limit."))
                    } else {
                        // Its own stack with no destinations, so clicking a tile stays in the sheet.
                        NavigationStack {
                            ScrollView {
                                ElementView(element: element, pageID: pageID, result: result,
                                            editing: false, delete: {}, isPreview: true)
                                    .padding(.vertical, 16)
                            }
                        }
                        .environment(\.albumNavigationDisabled, true)
                        .environment(\.elementPreview, true)
                    }
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.background.opacity(0.5))
    }

    private var summary: String {
        guard let result else { return "Calculating…" }
        let minutes = Int(result.tracks.reduce(0) { $0 + $1.duration } / 60)
        let time = minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
        if result.kind == .songs { return "\(result.tracks.count.counted("song")) · \(time)" }
        return "\(result.count.counted(String(result.kind.rawValue.dropLast()))) · \(result.tracks.count.counted("song")) · \(time)"
    }
}
