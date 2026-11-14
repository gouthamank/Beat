import SwiftUI
import XCTest
@testable import Beat

/// Page elements in each layout, for each kind of result, over `SnapshotLibrary`.
@MainActor
final class ElementSnapshotTests: XCTestCase {
    private var stores: SnapshotStores!

    override func setUp() async throws {
        stores = try await SnapshotStores.make(for: self)
    }

    /// An element showing `output`, newest first, laid out as `layout`.
    private func element(_ name: String, _ output: ResultKind, _ layout: ElementAppearance.Layout,
                         rows: Int = 1, columns: Int = 1, header: Bool = true) -> some View {
        // A fixed ID: the engine seeds per-filter shuffles with it.
        let index = ResultKind.allCases.firstIndex(of: output)!
        let filter = SmartFilter(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index)")!,
                                 name: name, output: output,
                                 steps: [.sort([SortKey(field: .field(.year), ascending: false),
                                                SortKey(field: .field(.title), ascending: true)])])
        var appearance = ElementAppearance.defaults(for: output)
        appearance.layout = layout
        appearance.rows = rows
        appearance.columns = columns
        appearance.showHeader = header
        let page = stores.pages.tree.nodes[0].id
        return ElementView(element: PageElement(filter: filter, appearance: appearance), pageID: page,
                           result: SnapshotLibrary.result(filter), editing: false, delete: {})
    }

    // MARK: Albums

    func testAlbumsShelf() { assertScreens(element("Albums", .albums, .shelf), stores: stores) }
    func testAlbumsGrid() { assertScreens(element("Albums", .albums, .grid, rows: 2), stores: stores) }
    func testAlbumsList() { assertScreens(element("Albums", .albums, .list, rows: 3, columns: 2), stores: stores) }
    /// iOS only: the Mac's capture draws the layer tree, which leaves out 3D transforms, so its side covers came out
    /// flat in the wrong places.
    func testAlbumsCoverFlow() throws {
        #if os(macOS)
        throw XCTSkip("The Mac's snapshot capture can't draw Cover Flow's 3D transforms.")
        #else
        assertScreens(element("Albums", .albums, .coverFlow), stores: stores)
        #endif
    }
    /// With an album from the middle in front (covers fan out on both sides) and the last (all on the left). Cover Flow
    /// alone, without its header: an element always starts at its first album.
    func testAlbumsCoverFlowFromTheMiddle() throws { try assertCoverFlow(startingAt: "First Light") }
    func testAlbumsCoverFlowAtTheEnd() throws { try assertCoverFlow(startingAt: "Deep Blue") }

    private func assertCoverFlow(startingAt title: String, testName: String = #function) throws {
        #if os(macOS)
        throw XCTSkip("The Mac's snapshot capture can't draw Cover Flow's 3D transforms.")
        #else
        let filter = SmartFilter(id: UUID(), name: "Albums", output: .albums,
                                 steps: [.sort([SortKey(field: .field(.year), ascending: false),
                                                SortKey(field: .field(.title), ascending: true)])])
        let albums = SnapshotLibrary.result(filter).albums
        let start = try XCTUnwrap(albums.first { $0.title == title }).id
        assertScreens(CoverFlowStartingAt(albums: albums, start: start), stores: stores, testName: testName)
        #endif
    }

    func testAlbumsTimeline() { assertScreens(element("Albums", .albums, .timeline), stores: stores) }
    func testAlbumsWithoutHeader() { assertScreens(element("Albums", .albums, .shelf, header: false), stores: stores) }

    // MARK: Songs, artists, genres

    func testSongsList() { assertScreens(element("Songs", .songs, .list, rows: 4, columns: 2), stores: stores) }
    func testSongsShelf() { assertScreens(element("Songs", .songs, .shelf, rows: 2), stores: stores) }
    func testArtistsShelf() { assertScreens(element("Artists", .artists, .shelf), stores: stores) }
    func testArtistsList() { assertScreens(element("Artists", .artists, .list, rows: 3), stores: stores) }
    func testGenresGrid() { assertScreens(element("Genres", .genres, .grid), stores: stores) }
    func testGenresList() { assertScreens(element("Genres", .genres, .list, rows: 4), stores: stores) }
}

/// Cover Flow sized as `ElementView` sizes it (smaller on a phone), starting at `start`.
private struct CoverFlowStartingAt: View {
    let albums: [Album]
    let start: PersistentID
    @Environment(\.compactLayout) private var compact

    var body: some View {
        let side = CoverFlowGeometry.side(for: .medium)
        CoverFlowElement(albums: albums, side: compact ? min(side, 200) : side,
                         spread: CoverFlowGeometry.spread(for: .regular), startingAt: start)
    }
}
