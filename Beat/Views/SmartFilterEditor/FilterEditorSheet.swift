import SwiftUI

/// Creates or edits an element, or the defaults new elements start from: the draft, the live preview, and what saving
/// and deleting do. Each platform lays it out (`ElementEditorLayout` in Platform/*/ElementEditor+*.swift): a window
/// with the preview beside the settings on the Mac, a navigation stack of forms on iPad and iPhone.
struct FilterEditorSheet: View {
    private let target: EditorTarget
    @State private var draft: EditableFilter
    @State private var appearance: ElementAppearance
    @State private var preview: FilterResult?
    @State private var confirmDelete = false
    /// The draft as opened, so closing with changes can ask first.
    private let original: (filter: EditableFilter, appearance: ElementAppearance)
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
        original = (draft.filter, draft.appearance)
    }

    private var pageID: UUID? {
        if case .page(let id) = target { id } else { nil }
    }
    private var isNew: Bool { pageID.map { pages.element(draft.id, on: $0) == nil } ?? false }
    private var element: PageElement { PageElement(filter: draft.makeFilter(), appearance: appearance) }
    private var canSave: Bool { !draft.name.trimmingCharacters(in: .whitespaces).isEmpty }
    private var hasChanges: Bool { draft != original.filter || appearance != original.appearance }

    var body: some View {
        ElementEditorLayout(
            draft: $draft, appearance: $appearance,
            context: ElementEditorContext(
                nameCaption: target == .defaults ? "Defaults for new elements" : nil,
                saveTitle: saveTitle, canSave: canSave, canDelete: pageID != nil && !isNew, hasChanges: hasChanges
            ),
            preview: { ElementPreview(element: element, pageID: pageID ?? standInPageID, result: preview) },
            save: save, cancel: { dismiss() }, delete: { confirmDelete = true }
        )
        .task(id: element) { await refreshPreview() }
        .environment(\.customFieldSamples, preview?.tracks ?? [])
        // Here rather than in the Appearance form, which isn't on screen while Show as changes on Rules.
        .onChange(of: draft.output) { _, output in appearance.fit(to: output) }
        // A custom field edited from inside the editor updates every element, and this unsaved draft too.
        .onChange(of: pages.customFields) { _, fields in
            draft.refreshCustomFields(fields)
            appearance.sortOverride = appearance.sortOverride?.refreshed(fields)
        }
        .confirmationDialog("Delete “\(draft.name)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let pageID { pages.deleteElement(draft.id, from: pageID) }
                dismiss()
            }
        } message: {
            Text("Its smart filter is deleted with it.")
        }
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

/// What a platform's editor layout shows around the draft.
struct ElementEditorContext {
    /// Under or beside the name: "Defaults for new elements" when editing those.
    let nameCaption: String?
    /// "Create", "Save" or "Save Defaults".
    let saveTitle: String
    /// The element has a name.
    let canSave: Bool
    /// An element already on a page (not a new one, not the defaults).
    let canDelete: Bool
    /// Edited since it opened: closing asks first.
    let hasChanges: Bool
}
