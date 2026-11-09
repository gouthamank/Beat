import XCTest
@testable import Beat

@MainActor
final class PageStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var pagesURL: URL { directory.appendingPathComponent("pages.json") }

    func testFirstLaunchSeedsHome() {
        let store = PageStore(directory: directory)
        XCTAssertEqual(store.tree.nodes.map(\.name), ["Home"])
        XCTAssertEqual(store.tree.nodes.first?.page?.elements.count, Presets.all.count)
    }

    func testEditsPersistAcrossLaunches() async throws {
        let store = PageStore(directory: directory)
        let folder = store.create(folder: true, in: nil)
        store.rename(folder, to: "Deep")
        let page = store.create(folder: false, in: folder)
        store.rename(page, to: "Auxiliary")
        let singles = PageElement(filter: SmartFilter(id: UUID(), name: "Singles", output: .albums))
        store.saveElement(singles, on: page)
        await store.flush()

        let reloaded = PageStore(directory: directory)
        XCTAssertEqual(reloaded.tree, store.tree)
        XCTAssertEqual(reloaded.tree.pages.map(\.path), ["Home", "Deep ▸ Auxiliary"])
        XCTAssertEqual(reloaded.element(singles.id, on: page), singles)
    }

    func testCorruptFileIsSetAsideNotOverwritten() async throws {
        let garbage = Data("{ not json".utf8)
        try garbage.write(to: pagesURL)

        let store = PageStore(directory: directory)
        XCTAssertEqual(store.tree.nodes.map(\.name), ["Home"], "falls back to defaults")

        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let backup = try XCTUnwrap(files.first { $0.hasPrefix("pages.corrupt-") })
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(backup)), garbage)

        store.create(folder: false, in: nil)
        await store.flush()
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(backup)), garbage, "the backup survives the next save")
    }

    func testEditingCustomFieldRewritesEveryUse() async throws {
        let store = PageStore(directory: directory)
        var catalog = CustomField(name: "Catalog No.", source: .album, extraction: .lastParentheses)
        store.saveCustomField(catalog)

        let pageA = store.create(folder: false, in: nil)
        let folder = store.create(folder: true, in: nil)
        let pageB = store.create(folder: false, in: folder)
        let sorted = PageElement(filter: SmartFilter(id: UUID(), name: "A", output: .albums,
                                                     steps: [.sort([SortKey(field: .custom(catalog), ascending: true)])]))
        var overridden = PageElement(filter: SmartFilter(id: UUID(), name: "B", output: .albums))
        overridden.appearance.sortOverride = SortKey(field: .custom(catalog), ascending: true)
        store.saveElement(sorted, on: pageA)
        store.saveElement(overridden, on: pageB)

        catalog.extraction = .pattern(#"AUX(\d+)"#)
        store.saveCustomField(catalog)

        XCTAssertEqual(store.element(sorted.id, on: pageA)?.filter.steps, [.sort([SortKey(field: .custom(catalog), ascending: true)])])
        XCTAssertEqual(store.element(overridden.id, on: pageB)?.appearance.sortOverride?.field, .custom(catalog))

        store.deleteCustomField(catalog.id)
        XCTAssertTrue(store.customFields.isEmpty)
        XCTAssertEqual(store.element(sorted.id, on: pageA)?.filter.steps, [.sort([SortKey(field: .custom(catalog), ascending: true)])],
                       "elements keep their copy after the definition is deleted")

        await store.flush()
        XCTAssertEqual(PageStore(directory: directory).customFields, [])
    }

    func testCustomFieldsPersist() async throws {
        let store = PageStore(directory: directory)
        let catalog = CustomField(name: "Catalog No.", source: .album, extraction: .lastBrackets)
        store.saveCustomField(catalog)
        await store.flush()
        XCTAssertEqual(PageStore(directory: directory).customFields, [catalog])
    }

    func testFileWithoutCustomFieldsStillLoads() throws {
        let json = #"{"version":1,"nodes":[{"id":"\#(UUID().uuidString)","name":"Old","symbol":"house","page":{"elements":[]}}]}"#
        try Data(json.utf8).write(to: pagesURL)
        let store = PageStore(directory: directory)
        XCTAssertEqual(store.tree.nodes.map(\.name), ["Old"])
        XCTAssertTrue(store.customFields.isEmpty)
    }

    func testElementEdits() {
        let store = PageStore(directory: nil)
        let page = store.create(folder: false, in: nil)
        let a = PageElement(filter: SmartFilter(id: UUID(), name: "A"))
        let b = PageElement(filter: SmartFilter(id: UUID(), name: "B"))
        store.saveElement(a, on: page)
        store.saveElement(b, on: page)
        store.moveElement(b.id, on: page, by: -1)
        XCTAssertEqual(store.node(page)?.page?.elements.map(\.filter.name), ["B", "A"])

        store.duplicateElement(a.id, on: page)
        XCTAssertEqual(store.node(page)?.page?.elements.map(\.filter.name), ["B", "A", "A Copy"])

        let home = store.tree.nodes[0].id
        store.moveElement(b.id, from: page, to: home)
        XCTAssertNil(store.element(b.id, on: page))
        XCTAssertNotNil(store.element(b.id, on: home))
    }

    func testRenameElementTrimsIgnoresBlankAndPersists() async throws {
        let store = PageStore(directory: directory)
        let page = store.create(folder: false, in: nil)
        let element = PageElement(filter: SmartFilter(id: UUID(), name: "Old"))
        store.saveElement(element, on: page)

        store.renameElement(element.id, on: page, to: "  New Name  ")
        XCTAssertEqual(store.element(element.id, on: page)?.filter.name, "New Name")
        store.renameElement(element.id, on: page, to: "   ")
        XCTAssertEqual(store.element(element.id, on: page)?.filter.name, "New Name", "a blank name is ignored")

        await store.flush()
        let reloaded = PageStore(directory: directory)
        XCTAssertEqual(reloaded.element(element.id, on: page)?.filter.name, "New Name")
    }

    func testSortOverrideReordersWithoutChangingMembership() {
        let tracks = (1...6).map { Track.fixture(id: PersistentID($0), title: "T\($0)", year: 2000 + $0) }
        let lib = PreparedLibrary(snapshot: .build(tracks: tracks))
        // Newest four by year, then shown oldest first.
        let filter = SmartFilter(id: UUID(), name: "T", output: .songs, steps: [
            .sort([SortKey(field: .field(.year), ascending: false)]),
            .limit(Limit(count: 4, unit: .songs)),
        ])
        var element = PageElement(filter: filter)
        let plain = SmartFilterEngine.evaluate(element.effectiveFilter, in: lib).tracks.map(\.id)
        element.appearance.sortOverride = SortKey(field: .field(.year), ascending: true)
        let reordered = SmartFilterEngine.evaluate(element.effectiveFilter, in: lib).tracks.map(\.id)

        XCTAssertEqual(plain, [6, 5, 4, 3])
        XCTAssertEqual(reordered, [3, 4, 5, 6])
    }
}
