import XCTest
@testable import Beat

final class PageTreeTests: XCTestCase {
    private func element(_ name: String) -> PageElement {
        PageElement(filter: SmartFilter(id: UUID(), name: name, output: .albums))
    }

    /// Deep ▸ DnB ▸ Auxiliary, a top-level page between folders, and an empty folder.
    private func sample() -> (tree: PageTree, deep: UUID, dnb: UUID, aux: UUID, loose: UUID, empty: UUID) {
        let aux = SidebarNode.page("Auxiliary", [element("Singles"), element("LPs")])
        let dnb = SidebarNode.folder("DnB", [aux])
        let deep = SidebarNode.folder("Deep", [dnb, .page("Ambient")])
        let loose = SidebarNode.page("Loose Page")
        let empty = SidebarNode.folder("Empty")
        return (PageTree(nodes: [deep, loose, empty]), deep.id, dnb.id, aux.id, loose.id, empty.id)
    }

    private func names(_ nodes: [SidebarNode]) -> [String] { nodes.map(\.name) }

    func testLookupAcrossLevels() {
        let s = sample()
        XCTAssertEqual(s.tree.node(s.aux)?.name, "Auxiliary")
        XCTAssertEqual(s.tree.location(of: s.aux)?.parent, s.dnb)
        XCTAssertNil(s.tree.location(of: s.loose)?.parent)
        XCTAssertEqual(s.tree.location(of: s.loose)?.index, 1)
        XCTAssertEqual(s.tree.pages.map(\.path), ["Deep ▸ DnB ▸ Auxiliary", "Deep ▸ Ambient", "Loose Page"])
        XCTAssertEqual(s.tree.pageCount(in: s.deep), 2)
        XCTAssertEqual(s.tree.firstPageID, s.aux)
    }

    func testAncestorsOutermostFirst() {
        let s = sample()
        XCTAssertEqual(s.tree.ancestors(of: s.aux), [s.deep, s.dnb])
        XCTAssertEqual(s.tree.ancestors(of: s.dnb), [s.deep])
        XCTAssertEqual(s.tree.ancestors(of: s.loose), [])
        XCTAssertEqual(s.tree.ancestors(of: UUID()), [])
    }

    func testOpeningNestsAndNeverRevisits() {
        let artist = Route.artist("a/t/o/s"), album = Route.album(7), other = Route.artist("guest")
        XCTAssertEqual(AppNavigator.opening(artist, on: []), [artist], "drills down from the page you're on")
        XCTAssertEqual(AppNavigator.opening(album, on: [artist]), [artist, album])
        XCTAssertEqual(AppNavigator.opening(other, on: [artist, album]), [artist, album, other])
        XCTAssertEqual(AppNavigator.opening(artist, on: [artist, album, other]), [artist], "back to it, not a copy")
        XCTAssertEqual(AppNavigator.opening(album, on: [artist, album]), [artist, album], "already there: no change")
    }

    func testSidebarItemStorageRoundTrips() {
        let items: [SidebarItem] = [.page(UUID()), .albums, .artists, .songs, .genres]
        for item in items {
            XCTAssertEqual(SidebarItem(storageString: item.storageString), item)
        }
        XCTAssertNil(SidebarItem(storageString: "page:not-a-uuid"))
        XCTAssertNil(SidebarItem(storageString: "playlists"))
        XCTAssertNil(SidebarItem(storageString: ""))
    }

    func testFoldersAndPagesMixAtTopLevel() {
        var s = sample()
        XCTAssertTrue(s.tree.insert(.page("Top"), into: nil, at: 0))
        XCTAssertTrue(s.tree.insert(.folder("Another"), into: nil))
        XCTAssertEqual(names(s.tree.nodes), ["Top", "Deep", "Loose Page", "Empty", "Another"])
    }

    func testPagesNeverTakeChildren() {
        var s = sample()
        XCTAssertFalse(s.tree.insert(.page("Child"), into: s.loose))
        XCTAssertFalse(s.tree.move(s.empty, into: s.aux))
        XCTAssertEqual(s.tree.node(s.empty)?.name, "Empty", "a refused move leaves the node in place")
        XCTAssertNil(s.tree.node(s.aux)?.children)
    }

    func testMoveBetweenFoldersAndLevels() {
        var s = sample()
        XCTAssertTrue(s.tree.move(s.aux, into: s.empty))
        XCTAssertEqual(s.tree.location(of: s.aux)?.parent, s.empty)
        XCTAssertEqual(s.tree.node(s.dnb)?.children?.count, 0)

        XCTAssertTrue(s.tree.move(s.aux, into: nil, at: 0))
        XCTAssertEqual(names(s.tree.nodes), ["Auxiliary", "Deep", "Loose Page", "Empty"])
        XCTAssertEqual(s.tree.node(s.aux)?.page?.elements.count, 2, "elements travel with the page")
    }

    func testMoveWithinSameLevelUsesIndexBeforeMove() {
        var s = sample()
        // Move "Deep" (index 0) to before "Empty" (index 2): it lands between Loose Page and Empty.
        XCTAssertTrue(s.tree.move(s.deep, into: nil, at: 2))
        XCTAssertEqual(names(s.tree.nodes), ["Loose Page", "Deep", "Empty"])
    }

    func testFolderCannotMoveIntoItselfOrDescendant() {
        var s = sample()
        XCTAssertFalse(s.tree.move(s.deep, into: s.deep))
        XCTAssertFalse(s.tree.move(s.deep, into: s.dnb))
        XCTAssertEqual(names(s.tree.nodes), ["Deep", "Loose Page", "Empty"])
        XCTAssertTrue(s.tree.move(s.dnb, into: s.empty), "moving into an unrelated folder is fine")
    }

    func testRemoveDeletesSubtree() {
        var s = sample()
        XCTAssertEqual(s.tree.remove(s.deep)?.name, "Deep")
        XCTAssertNil(s.tree.node(s.aux))
        XCTAssertEqual(names(s.tree.nodes), ["Loose Page", "Empty"])
    }

    func testDuplicateGivesFreshIDsThroughout() throws {
        var s = sample()
        let copyID = try XCTUnwrap(s.tree.duplicate(s.deep))
        XCTAssertEqual(names(s.tree.nodes), ["Deep", "Deep Copy", "Loose Page", "Empty"])

        let original = try XCTUnwrap(s.tree.node(s.deep))
        let copy = try XCTUnwrap(s.tree.node(copyID))
        func allIDs(_ n: SidebarNode) -> [UUID] {
            [n.id] + (n.page?.elements.map(\.id) ?? []) + (n.children ?? []).flatMap(allIDs)
        }
        XCTAssertTrue(Set(allIDs(original)).isDisjoint(with: allIDs(copy)))
        XCTAssertEqual(allIDs(original).count, allIDs(copy).count)
    }

    func testUpdatePageEditsElementsOnlyOnPages() {
        var s = sample()
        s.tree.updatePage(s.aux) { $0.elements.removeFirst() }
        XCTAssertEqual(s.tree.node(s.aux)?.page?.elements.map(\.filter.name), ["LPs"])
        s.tree.updatePage(s.deep) { $0.elements.append(self.element("Nope")) }
        XCTAssertNotNil(s.tree.node(s.deep)?.children, "a folder stays a folder")
    }

    func testUpdateElementsReachesEveryDepth() {
        var s = sample()
        s.tree.insert(.page("Top", [element("T")]), into: nil)
        s.tree.updateElements { $0.filter.name += "!" }
        let names = s.tree.pages.flatMap { s.tree.node($0.id)?.page?.elements.map(\.filter.name) ?? [] }
        XCTAssertEqual(names, ["Singles!", "LPs!", "T!"])
    }

    func testCodableRoundTripWithPlainKeys() throws {
        let s = sample()
        let data = try JSONEncoder().encode(s.tree)
        XCTAssertEqual(try JSONDecoder().decode(PageTree.self, from: data), s.tree)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"folder\""))
        XCTAssertTrue(json.contains("\"page\""))
        XCTAssertFalse(json.contains("\"_0\":[{\"id\""), "sidebar nodes use plain keys")
    }

    func testAppearanceDecodesWithMissingFields() throws {
        let appearance = try JSONDecoder().decode(ElementAppearance.self, from: Data(#"{"layout":"grid"}"#.utf8))
        XCTAssertEqual(appearance.layout, .grid)
        XCTAssertEqual(appearance.size, .medium)
        XCTAssertTrue(appearance.showHeader)
        XCTAssertNil(appearance.sortOverride)
    }

    func testListLayoutForEveryKindWithColumns() {
        for kind in ResultKind.allCases {
            XCTAssertTrue(ElementAppearance.layouts(for: kind).contains(.list), "\(kind)")
        }
        var appearance = ElementAppearance.defaults(for: .albums)
        appearance.layout = .list
        appearance.rows = 40
        appearance.columns = 9
        appearance.fit(to: .artists)
        XCTAssertEqual(appearance.layout, .list, "albums → artists keeps List")
        XCTAssertEqual(appearance.rows, 25, "list rows are per column, up to 25")
        XCTAssertEqual(appearance.columns, 4)
    }

    func testAppearanceWithoutColumnsDecodesAsOneColumn() throws {
        let appearance = try JSONDecoder().decode(ElementAppearance.self, from: Data(#"{"layout":"list","rows":10}"#.utf8))
        XCTAssertEqual(appearance.columns, 1)
    }

    func testAppearanceFitsNewOutput() {
        var appearance = ElementAppearance.defaults(for: .albums)
        appearance.layout = .grid
        appearance.fit(to: .songs)
        XCTAssertEqual(appearance.layout, .list)
        XCTAssertEqual(appearance.rows, ElementAppearance.defaultRows(layout: .list, output: .songs))

        appearance.rows = 50
        appearance.layout = .shelf
        appearance.fit(to: .albums)
        XCTAssertEqual(appearance.rows, 3, "rows clamp to the album shelf's range")
    }
}
