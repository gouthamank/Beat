import SwiftUI

extension EnvironmentValues {
    /// Songs the custom field sheet checks first: the editor's current preview, so examples are relevant.
    @Entry var customFieldSamples: [Track] = []
}

/// Picks what to sort by: Random, a built-in field or a custom field. Also creates and manages custom fields,
/// so both the Sort step and the Order override get them without extra buttons.
struct SortFieldPicker: View {
    let title: String
    @Binding var selection: SortField?
    /// Offers "As filtered" (nil), for the appearance's sort override.
    var allowsNone = false
    @Environment(PageStore.self) private var pages
    @State private var creating: CustomField?
    @State private var managing = false

    private enum Choice: Hashable {
        case none
        case sort(SortField)
        case newCustom
        case manage
    }

    var body: some View {
        Picker(title, selection: Binding<Choice>(
            get: { selection.map(Choice.sort) ?? .none },
            set: { choice in
                switch choice {
                case .none: selection = nil
                case .sort(let field): selection = field
                case .newCustom: creating = .new()
                case .manage: managing = true
                }
            }
        )) {
            if allowsNone {
                Text("As filtered").tag(Choice.none)
                Divider()
            }
            Text("Random").tag(Choice.sort(.random))
            Divider()
            ForEach(Field.sortable, id: \.self) { Text($0.title).tag(Choice.sort(.field($0))) }
            Section("Custom") {
                ForEach(pages.customFields) { Text($0.name).tag(Choice.sort(.custom($0))) }
                if case .custom(let field)? = selection, !pages.customFields.contains(field) {
                    Text("\(field.name) (deleted)").tag(Choice.sort(.custom(field)))
                }
                Text("New Custom Field…").tag(Choice.newCustom)
                if !pages.customFields.isEmpty {
                    Text("Edit Custom Fields…").tag(Choice.manage)
                }
            }
        }
        .sheet(item: $creating) { field in
            CustomFieldSheet(field: field, isNew: true) { saved in
                pages.saveCustomField(saved)
                selection = .custom(saved)
            }
        }
        .sheet(isPresented: $managing) { CustomFieldsManager() }
    }
}

/// Creates or edits one custom field, with a live check of what it extracts.
struct CustomFieldSheet: View {
    let isNew: Bool
    let save: (CustomField) -> Void
    @State private var field: CustomField
    @State private var mode: Mode
    @State private var pattern: String
    @State private var check: Check?
    @Environment(LibraryStore.self) private var library
    @Environment(\.customFieldSamples) private var samples
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable {
        case parentheses = "Text in last ( )"
        case brackets = "Text in last [ ]"
        case pattern = "Pattern"
    }

    private struct Example: Sendable {
        let source: String
        let value: String?
    }

    private struct Check: Sendable {
        let matches: Int
        let total: Int
        let examples: [Example]
    }

    init(field: CustomField, isNew: Bool, save: @escaping (CustomField) -> Void) {
        self.isNew = isNew
        self.save = save
        _field = State(initialValue: field)
        switch field.extraction {
        case .lastParentheses:
            _mode = State(initialValue: .parentheses)
            _pattern = State(initialValue: "")
        case .lastBrackets:
            _mode = State(initialValue: .brackets)
            _pattern = State(initialValue: "")
        case .pattern(let p):
            _mode = State(initialValue: .pattern)
            _pattern = State(initialValue: p)
        }
    }

    private var current: CustomField {
        var f = field
        f.name = f.name.trimmingCharacters(in: .whitespaces)
        f.extraction = switch mode {
        case .parentheses: .lastParentheses
        case .brackets: .lastBrackets
        case .pattern: .pattern(pattern)
        }
        return f
    }

    private var canSave: Bool { !current.name.isEmpty && current.isValid }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $field.name, prompt: Text("e.g. Catalog No."))
                        .autocorrectionDisabled()
                    Picker("Source", selection: $field.source) {
                        ForEach(CustomField.sources, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Extract", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    if mode == .pattern {
                        TextField("Pattern", text: $pattern, prompt: Text(#"e.g. AUX\w+"#))
                            .font(.body.monospaced())
                            .autocorrectionDisabled()
                        if !pattern.isEmpty, !current.isValid {
                            Text("Not a valid regular expression.").font(.caption).foregroundStyle(.red)
                        }
                    }
                } footer: {
                    if mode == .pattern {
                        Text("Uses the first match, or its first capture group if the pattern has one. Case doesn't matter.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Check") {
                    if let check {
                        Text("Matches \(check.matches.formatted()) of \(check.total.counted("song"))")
                            .foregroundStyle(.secondary)
                        ForEach(check.examples, id: \.source) { example in
                            LabeledContent {
                                Text(example.value ?? "no match")
                                    .monospaced()
                                    .foregroundStyle(example.value == nil ? .tertiary : .primary)
                            } label: {
                                Text(example.source).lineLimit(1)
                            }
                        }
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Create" : "Save") {
                    save(current)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .beatGlassButtonStyle(prominent: true)
                .disabled(!canSave)
            }
            .padding(14)
        }
        .sheetSize(width: 480, height: 540)
        .task(id: current) { await runCheck() }
    }

    /// Counts matches across the library off the main actor; picks examples from the preview first.
    private func runCheck() async {
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        let field = current
        let tracks = library.snapshot.tracks
        let samples = samples
        let result = await Task.detached(priority: .userInitiated) { () -> Check in
            let extract = field.extractor()
            let matches = tracks.reduce(0) { $0 + (extract($1) == nil ? 0 : 1) }
            var seen = Set<String>()
            var examples: [Example] = []
            func add(_ track: Track) {
                let source = SmartFilterEngine.text(field.source, track)
                guard examples.count < 8, !source.isEmpty, seen.insert(source).inserted else { return }
                examples.append(Example(source: source, value: extract(track)))
            }
            samples.forEach(add)
            if examples.isEmpty {
                for track in tracks where extract(track) != nil {
                    add(track)
                    if examples.count == 8 { break }
                }
            }
            return Check(matches: matches, total: tracks.count, examples: examples)
        }.value
        guard !Task.isCancelled else { return }
        check = result
    }
}

/// Lists custom fields for editing and deleting.
struct CustomFieldsManager: View {
    @Environment(PageStore.self) private var pages
    @Environment(\.dismiss) private var dismiss
    @State private var editing: CustomField?
    @State private var pendingDelete: CustomField?

    var body: some View {
        VStack(spacing: 0) {
            List {
                ForEach(pages.customFields) { field in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.name)
                            Text(field.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button { editing = field } label: { Image(systemName: "slider.horizontal.3") }
                            .help("Edit")
                        Button { pendingDelete = field } label: { Image(systemName: "trash") }
                            .help("Delete")
                    }
                    .buttonStyle(.borderless)
                    .padding(.vertical, 3)
                }
            }
            #if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: false))
            #else
            .listStyle(.inset)
            #endif
            .overlay {
                if pages.customFields.isEmpty {
                    ContentUnavailableView("No Custom Fields", systemImage: "function")
                }
            }

            Divider()
            HStack {
                Button("New Custom Field…") { editing = .new() }
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .beatGlassButtonStyle(prominent: true)
            }
            .padding(14)
        }
        .sheetSize(width: 460, height: 360)
        .sheet(item: $editing) { field in
            CustomFieldSheet(field: field, isNew: !pages.customFields.contains { $0.id == field.id }) { pages.saveCustomField($0) }
        }
        .confirmationDialog("Delete “\(pendingDelete?.name ?? "")”?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let field = pendingDelete { pages.deleteCustomField(field.id) }
            }
        } message: {
            Text("Elements already sorted by it keep their order.")
        }
    }
}
