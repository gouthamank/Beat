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
}
