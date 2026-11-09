import XCTest
@testable import Beat

@MainActor
final class SettingsArchiveTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "SettingsArchiveTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
    }

    func testCapturesOnlyKnownPreferencesWithTheirTypes() throws {
        defaults.set(false, forKey: "appearance.coverColours")
        defaults.set(240.5, forKey: "songs.albumArtWidth")
        defaults.set("songs", forKey: LibraryPage.hiddenKey)
        defaults.set(Data([1, 2, 3]), forKey: ArtistSorts.storageKey)
        defaults.set(0.4, forKey: "volume")

        let archive = SettingsArchive.capture(nodes: [], customFields: [], defaults: defaults)
        XCTAssertEqual(archive.preferences["appearance.coverColours"], .bool(false))
        XCTAssertEqual(archive.preferences["songs.albumArtWidth"], .double(240.5))
        XCTAssertEqual(archive.preferences[LibraryPage.hiddenKey], .string("songs"))
        XCTAssertEqual(archive.preferences[ArtistSorts.storageKey], .data(Data([1, 2, 3])))
        XCTAssertNil(archive.preferences["volume"], "window state isn't a setting")
    }

    func testRoundTripsThroughAFile() throws {
        let page = SidebarNode.page("Mixes", [PageElement(filter: SmartFilter(id: UUID(), name: "Singles", output: .albums))])
        let tree = [SidebarNode.folder("DJ", [page])]
        defaults.set(true, forKey: "lyrics.online")
        defaults.set(3, forKey: "visualizer.style")
        let archive = SettingsArchive.capture(nodes: tree, customFields: [], defaults: defaults)

        let decoded = try SettingsArchive.decode(archive.encoded())
        XCTAssertEqual(decoded.nodes, tree)
        XCTAssertEqual(decoded.preferences["lyrics.online"], .bool(true))
        XCTAssertEqual(decoded.preferences["visualizer.style"], .int(3))
    }

    func testApplyingReplacesPreferencesAndResetsMissingOnes() {
        defaults.set(false, forKey: "appearance.coverColours")
        defaults.set("songs", forKey: LibraryPage.hiddenKey)
        defaults.set(0.4, forKey: "volume")
        let archive = SettingsArchive(exportedAt: .now, nodes: [], customFields: [],
                                      preferences: ["appearance.coverColours": .bool(true), "unknown.key": .int(1)])
        archive.applyPreferences(to: defaults)

        XCTAssertEqual(defaults.object(forKey: "appearance.coverColours") as? Bool, true)
        XCTAssertNil(defaults.object(forKey: LibraryPage.hiddenKey), "not in the file: back to the default")
        XCTAssertNil(defaults.object(forKey: "unknown.key"), "unknown keys are ignored")
        XCTAssertEqual(defaults.double(forKey: "volume"), 0.4, "window state is left alone")
    }

    func testRejectsFilesThatArentSettings() {
        XCTAssertThrowsError(try SettingsArchive.decode(Data(#"{"nodes": []}"#.utf8)))
        XCTAssertThrowsError(try SettingsArchive.decode(Data(#"{"format": "beat-settings", "version": 2}"#.utf8)))
    }

    func testImportReplacesThePagesAndPersists() async throws {
        let store = PageStore(directory: directory)
        let imported = [SidebarNode.page("Imported")]
        store.replace(with: SettingsArchive(exportedAt: .now, nodes: imported, customFields: [], preferences: [:]))
        await store.flush()

        XCTAssertEqual(store.tree.nodes, imported)
        XCTAssertEqual(PageStore(directory: directory).tree.nodes, imported)
    }

    func testImportingAnEmptyTreeKeepsAHomePage() {
        let store = PageStore(directory: directory)
        store.replace(with: SettingsArchive(exportedAt: .now, nodes: [], customFields: [], preferences: [:]))
        XCTAssertEqual(store.tree.nodes.map(\.name), ["Home"])
    }
}
