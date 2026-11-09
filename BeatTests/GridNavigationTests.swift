import XCTest
@testable import Beat

final class GridNavigationTests: XCTestCase {
    // 10 items in rows of 4:
    //  0 1 2 3
    //  4 5 6 7
    //  8 9
    private let rows = GridOrder.rows(columns: 4)

    func testRowOrderMovesByItemAndByRow() {
        XCTAssertEqual(GridNavigation.move(.right, from: 3, count: 10, order: rows), 4, "right carries on into the next row")
        XCTAssertEqual(GridNavigation.move(.left, from: 4, count: 10, order: rows), 3)
        XCTAssertEqual(GridNavigation.move(.down, from: 1, count: 10, order: rows), 5)
        XCTAssertEqual(GridNavigation.move(.up, from: 5, count: 10, order: rows), 1)
    }

    func testRowOrderStopsAtEdgesAndLandsInShortLastRow() {
        XCTAssertEqual(GridNavigation.move(.up, from: 2, count: 10, order: rows), 2, "top row: stays")
        XCTAssertEqual(GridNavigation.move(.left, from: 0, count: 10, order: rows), 0)
        XCTAssertEqual(GridNavigation.move(.right, from: 9, count: 10, order: rows), 9)
        XCTAssertEqual(GridNavigation.move(.down, from: 7, count: 10, order: rows), 9, "nothing below: the last row's last item")
        XCTAssertEqual(GridNavigation.move(.down, from: 9, count: 10, order: rows), 9, "last row: stays")
    }

    // 7 items in columns of 3 (a shelf filled column by column):
    //  0 3 6
    //  1 4
    //  2 5
    private let columns = GridOrder.columns(rows: 3)

    func testColumnOrderMovesWithinColumnAndAcross() {
        XCTAssertEqual(GridNavigation.move(.down, from: 0, count: 7, order: columns), 1)
        XCTAssertEqual(GridNavigation.move(.down, from: 2, count: 7, order: columns), 2, "bottom of a column: stays")
        XCTAssertEqual(GridNavigation.move(.up, from: 3, count: 7, order: columns), 3, "top of a column: stays")
        XCTAssertEqual(GridNavigation.move(.right, from: 1, count: 7, order: columns), 4)
        XCTAssertEqual(GridNavigation.move(.right, from: 4, count: 7, order: columns), 6, "short last column: its last item")
        XCTAssertEqual(GridNavigation.move(.left, from: 6, count: 7, order: columns), 3)
        XCTAssertEqual(GridNavigation.move(.left, from: 1, count: 7, order: columns), 1)
    }

    func testOneRowShelfOnlyMovesSideways() {
        let shelf = GridOrder.columns(rows: 1)
        XCTAssertEqual(GridNavigation.move(.right, from: 2, count: 5, order: shelf), 3)
        XCTAssertEqual(GridNavigation.move(.down, from: 2, count: 5, order: shelf), 2)
        XCTAssertEqual(GridNavigation.move(.up, from: 2, count: 5, order: shelf), 2)
    }

    func testAdaptiveColumnsMatchesHowManyMinimumWidthTilesFit() {
        // 24 pt insets, 22 pt gaps, 160 pt tiles: 4 fit in 800 (4×160 + 3×22 = 706 ≤ 752), 5 don't (888).
        XCTAssertEqual(GridNavigation.adaptiveColumns(width: 800, minimum: 160, spacing: 22, inset: 24), 4)
        XCTAssertEqual(GridNavigation.adaptiveColumns(width: 0, minimum: 160, spacing: 22, inset: 24), 1, "never fewer than one")
    }
}
