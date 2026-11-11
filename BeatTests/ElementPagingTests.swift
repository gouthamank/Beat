import XCTest
@testable import Beat

final class ElementPagingTests: XCTestCase {
    func testColumnsAndRowsRoundUp() {
        XCTAssertEqual(ElementPaging.columnsNeeded(count: 50, rows: 5), 10)
        XCTAssertEqual(ElementPaging.columnsNeeded(count: 51, rows: 5), 11)
        XCTAssertEqual(ElementPaging.rowsNeeded(count: 50, columns: 2), 25)
        XCTAssertEqual(ElementPaging.rowsNeeded(count: 3, columns: 2), 2)
        XCTAssertEqual(ElementPaging.columnsNeeded(count: 10, rows: 0), 0, "no rows, no columns")
    }

    func testCappedOnlyWhenMoreThanOneScreenful() {
        XCTAssertTrue(ElementPaging.isCapped(count: 11, rows: 5, columns: 2))
        XCTAssertFalse(ElementPaging.isCapped(count: 10, rows: 5, columns: 2))
        XCTAssertFalse(ElementPaging.isCapped(count: 100, rows: ElementAppearance.allRows, columns: 2), "All never caps")
    }

    func testFitKeepsAllRowsForGridAndListOnly() {
        var grid = ElementAppearance()
        grid.layout = .grid
        grid.rows = ElementAppearance.allRows
        grid.fit(to: .albums)
        XCTAssertEqual(grid.rows, ElementAppearance.allRows)

        var list = ElementAppearance()
        list.layout = .list
        list.rows = ElementAppearance.allRows
        list.fit(to: .songs)
        XCTAssertEqual(list.rows, ElementAppearance.allRows)

        var shelf = ElementAppearance()
        shelf.layout = .shelf
        shelf.rows = ElementAppearance.allRows
        shelf.fit(to: .albums)
        XCTAssertEqual(shelf.rows, 1, "shelves always have rows")
    }

    func testShowFooterDefaultsOnWhenMissing() throws {
        let decoded = try JSONDecoder().decode(ElementAppearance.self, from: Data(#"{"layout":"grid"}"#.utf8))
        XCTAssertTrue(decoded.showFooter)
        var off = ElementAppearance()
        off.showFooter = false
        let roundTrip = try JSONDecoder().decode(ElementAppearance.self, from: JSONEncoder().encode(off))
        XCTAssertFalse(roundTrip.showFooter)
    }

    // MARK: Fill

    func testDownMatchesTheOldOrder() {
        XCTAssertEqual(ElementPaging.columns(count: 5, rows: 2, fill: .down), [[0, 1], [2, 3], [4]])
    }

    func testAcrossRunsEachRowAllTheWayAlong() {
        // 2 rows: 0 1 2 3 4
        //         5 6 7 8 9
        XCTAssertEqual(ElementPaging.columns(count: 10, rows: 2, fill: .across), [[0, 5], [1, 6], [2, 7], [3, 8], [4, 9]])
        // An odd count leaves the last row a column short: 0 1 2 3 4 / 5 6 7 8.
        XCTAssertEqual(ElementPaging.columns(count: 9, rows: 2, fill: .across), [[0, 5], [1, 6], [2, 7], [3, 8], [4]])
    }

    func testAcrossInThreeRows() {
        // 0 1 2 / 3 4 5 / 6: also a 3-column list that fits.
        XCTAssertEqual(ElementPaging.columns(count: 7, rows: 3, fill: .across), [[0, 3, 6], [1, 4], [2, 5]])
    }

    func testOneRowIsTheSameEitherWay() {
        XCTAssertEqual(ElementPaging.columns(count: 4, rows: 1, fill: .across), ElementPaging.columns(count: 4, rows: 1, fill: .down))
    }

    func testDegenerateSizesDontCrash() {
        XCTAssertEqual(ElementPaging.columns(count: 3, rows: 0, fill: .across), [[0], [1], [2]])
        XCTAssertEqual(ElementPaging.columns(count: 0, rows: 2, fill: .across), [])
    }

    func testFillFollowsTheLayoutUntilChosen() throws {
        var look = try JSONDecoder().decode(ElementAppearance.self, from: Data(#"{"layout":"grid"}"#.utf8))
        XCTAssertNil(look.fill, "saved before Fill existed")
        XCTAssertEqual(look.effectiveFill, .across, "grids read across")
        look.layout = .list
        XCTAssertEqual(look.effectiveFill, .down, "lists read down")
        look.setFill(.across)
        XCTAssertEqual(look.fill, .across, "chosen, so it sticks")
        look.layout = .grid
        XCTAssertEqual(look.effectiveFill, .across)
        look.setFill(.across)
        XCTAssertNil(look.fill, "the layout's own default goes back to following it")
        var down = ElementAppearance()
        down.setFill(.down)
        XCTAssertEqual(try JSONDecoder().decode(ElementAppearance.self, from: JSONEncoder().encode(down)).fill, .down)
    }
}
