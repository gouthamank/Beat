import Foundation
import Observation

/// Owns the sidebar tree of folders and pages, and the evaluated results of the elements on screen.
@MainActor
@Observable
final class PageStore {
    private(set) var tree: PageTree
    /// Custom sort field definitions to pick from. Sort keys embed their own copy.
    private(set) var customFields: [CustomField] = []
    private(set) var results: [UUID: FilterResult] = [:]

    /// The element each result was computed from, so only edited elements are re-evaluated.
    @ObservationIgnored private var evaluated: [UUID: PageElement] = [:]
    @ObservationIgnored private var prepared: (key: LibraryKey, library: PreparedLibrary)?
    @ObservationIgnored private var latestKey: LibraryKey?
    @ObservationIgnored private let directory: URL?
    /// Saves run one after another, so an older write can never land after a newer one.
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    struct LibraryKey: Equatable, Sendable {
        let library: Int
        let history: Int
    }

    private struct Saved: Codable {
        var version = 1
        var nodes: [SidebarNode]
        var customFields: [CustomField] = []

        init(nodes: [SidebarNode], customFields: [CustomField]) {
            self.nodes = nodes
            self.customFields = customFields
        }

        // Files saved before custom fields existed have no `customFields` key.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
            nodes = try c.decode([SidebarNode].self, forKey: .nodes)
            customFields = try c.decodeIfPresent([CustomField].self, forKey: .customFields) ?? []
        }
    }

    init(directory: URL? = PageStore.defaultDirectory) {
        self.directory = directory
        tree = PageTree(nodes: [Presets.homePage()])
        guard let url = directory?.appendingPathComponent("pages.json"),
              let data = try? Data(contentsOf: url) else { return }
        do {
            let saved = try JSONDecoder().decode(Saved.self, from: data)
            tree = PageTree(nodes: saved.nodes)
            customFields = saved.customFields
        } catch {
            // Keep the unreadable file out of the way so the next save can't overwrite the user's tree.
            let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
            try? FileManager.default.moveItem(at: url, to: url.deletingLastPathComponent().appendingPathComponent("pages.corrupt-\(stamp).json"))
        }
    }

    func node(_ id: UUID) -> SidebarNode? { tree.node(id) }

    func element(_ id: UUID, on pageID: UUID) -> PageElement? {
        tree.node(pageID)?.page?.elements.first { $0.id == id }
    }

    // MARK: Tree

    /// Creates a folder or page inside `parent` (nil for the top level) and returns its ID.
    @discardableResult
    func create(folder: Bool, in parent: UUID?, at index: Int? = nil) -> UUID {
        let node: SidebarNode = folder ? .folder("New Folder") : .page("New Page")
        tree.insert(node, into: parent, at: index)
        save()
        return node.id
    }

    /// Creates a sibling right after `id`, at the same level.
    @discardableResult
    func create(folder: Bool, below id: UUID) -> UUID {
        let at = tree.location(of: id)
        return create(folder: folder, in: at?.parent, at: at.map { $0.index + 1 })
    }

    func insert(_ node: SidebarNode, into parent: UUID?, at index: Int? = nil) {
        tree.insert(node, into: parent, at: index)
        save()
    }

    func rename(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        tree.update(id) { $0.name = name }
        save()
    }

    func setSymbol(_ id: UUID, _ symbol: String) {
        tree.update(id) { $0.symbol = symbol }
        save()
    }

    @discardableResult
    func move(_ id: UUID, into parent: UUID?, at index: Int? = nil) -> Bool {
        guard tree.move(id, into: parent, at: index) else { return false }
        save()
        return true
    }

    @discardableResult
    func duplicate(_ id: UUID) -> UUID? {
        let copy = tree.duplicate(id)
        save()
        return copy
    }

    func delete(_ id: UUID) {
        tree.remove(id)
        save()
    }

    // MARK: Elements

    /// Replaces the element with the same ID on the page, or appends it.
    func saveElement(_ element: PageElement, on pageID: UUID) {
        tree.updatePage(pageID) { page in
            if let i = page.elements.firstIndex(where: { $0.id == element.id }) {
                page.elements[i] = element
            } else {
                page.elements.append(element)
            }
        }
        save()
    }

    func deleteElement(_ id: UUID, from pageID: UUID) {
        tree.updatePage(pageID) { $0.elements.removeAll { $0.id == id } }
        results[id] = nil
        evaluated[id] = nil
        save()
    }

    /// An element's name lives on its filter. Blank names are ignored, as with sidebar items.
    func renameElement(_ id: UUID, on pageID: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        tree.updatePage(pageID) { page in
            guard let i = page.elements.firstIndex(where: { $0.id == id }) else { return }
            page.elements[i].filter.name = name
        }
        save()
    }

    func duplicateElement(_ id: UUID, on pageID: UUID) {
        tree.updatePage(pageID) { page in
            guard let i = page.elements.firstIndex(where: { $0.id == id }) else { return }
            var copy = page.elements[i].withNewID()
            copy.filter.name += " Copy"
            page.elements.insert(copy, at: i + 1)
        }
        save()
    }

    func moveElement(_ id: UUID, on pageID: UUID, by offset: Int) {
        tree.updatePage(pageID) { page in
            guard let i = page.elements.firstIndex(where: { $0.id == id }), page.elements.indices.contains(i + offset) else { return }
            page.elements.swapAt(i, i + offset)
        }
        save()
    }

    func moveElement(_ id: UUID, from pageID: UUID, to otherPageID: UUID) {
        guard let element = element(id, on: pageID), tree.node(otherPageID)?.page != nil else { return }
        tree.updatePage(pageID) { $0.elements.removeAll { $0.id == id } }
        tree.updatePage(otherPageID) { $0.elements.append(element) }
        save()
    }

    // MARK: Custom fields

    /// Adds or replaces a definition, and updates every sort key embedding it so all elements re-sort.
    func saveCustomField(_ field: CustomField) {
        if let i = customFields.firstIndex(where: { $0.id == field.id }) {
            customFields[i] = field
        } else {
            customFields.append(field)
        }
        let fields = customFields
        tree.updateElements { $0.refreshCustomFields(fields) }
        save()
    }

    /// Removes the definition from the picker. Elements sorted by it keep their embedded copy.
    func deleteCustomField(_ id: UUID) {
        customFields.removeAll { $0.id == id }
        save()
    }

    // MARK: Results

    /// Evaluates the page's elements that are new or changed since their last result.
    /// Only the page on screen is evaluated, so a deep tree costs nothing until it's opened.
    func evaluate(pageID: UUID, snapshot: LibrarySnapshot, history: [PersistentID: PlayHistoryStore.Stats], key: LibraryKey) async {
        guard !snapshot.tracks.isEmpty, let page = tree.node(pageID)?.page else { return }
        if latestKey != key {
            latestKey = key
            prepared = nil
            evaluated = [:]
        }
        let stale = page.elements.filter { evaluated[$0.id] != $0 }
        guard !stale.isEmpty else { return }
        let cached = prepared?.library
        let (library, computed) = await Task.detached(priority: .userInitiated) {
            let library = cached ?? PreparedLibrary(snapshot: snapshot, history: history)
            return (library, stale.map { ($0, SmartFilterEngine.evaluate($0.effectiveFilter, in: library)) })
        }.value
        // A newer library or history arrived while this ran; its own evaluation will follow.
        guard latestKey == key else { return }
        prepared = (key, library)
        for (element, result) in computed {
            evaluated[element.id] = element
            results[element.id] = result
        }
    }

    // MARK: Settings file

    /// Everything a settings file needs from the pages, plus the given preferences.
    func archive(defaults: UserDefaults = .standard) -> SettingsArchive {
        SettingsArchive.capture(nodes: tree.nodes, customFields: customFields, defaults: defaults)
    }

    /// Replaces every folder, page, element and custom field with a settings file's. Results are worked
    /// out again as pages come on screen.
    func replace(with archive: SettingsArchive) {
        tree = PageTree(nodes: archive.nodes.isEmpty ? [Presets.homePage()] : archive.nodes)
        customFields = archive.customFields
        results = [:]
        evaluated = [:]
        save()
    }

    // MARK: Persistence

    private func save() {
        guard let directory else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try? encoder.encode(Saved(nodes: tree.nodes, customFields: customFields))
        let previous = saveTask
        saveTask = Task.detached(priority: .utility) {
            await previous?.value
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? data?.write(to: directory.appendingPathComponent("pages.json"), options: .atomic)
        }
    }

    /// Waits for pending saves. Used by tests.
    func flush() async { await saveTask?.value }

    nonisolated static var defaultDirectory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Beat", isDirectory: true)
    }
}
