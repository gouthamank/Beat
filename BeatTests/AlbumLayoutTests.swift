import XCTest
@testable import Beat

final class AlbumLayoutTests: XCTestCase {
    // MARK: Timeline

    /// Items' years by index: two in 2011, one each in 2009 and 2013, two without a year.
    private let years = [2011, 0, 2009, 2011, 2013, 0]
    private func group(newestFirst: Bool) -> [(year: Int?, indices: [Int])] {
        TimelineYears.group(years.count, year: { self.years[$0] }, newestFirst: newestFirst)
    }

    func testTimelineOldestFirst() {
        let groups = group(newestFirst: false)
        XCTAssertEqual(groups.map(\.year), [2009, 2011, 2013, nil])
        XCTAssertEqual(groups[1].indices, [0, 3], "the element's own order within a year")
    }

    func testTimelineNewestFirstStillPutsNoYearLast() {
        let groups = group(newestFirst: true)
        XCTAssertEqual(groups.map(\.year), [2013, 2011, 2009, nil])
        XCTAssertEqual(groups.last?.indices, [1, 5])
    }

    func testTimelineEmpty() {
        XCTAssertTrue(TimelineYears.group(0, year: { _ in 2000 }, newestFirst: false).isEmpty)
    }

    func testYearsKeepOneHeightByDefault() {
        // 20 albums, 2 rows: 10 columns wide.
        XCTAssertEqual(TimelineYears.grid(count: 20, rows: 2, maxColumns: nil, fill: .down).count, 10)
    }

    func testYearsGrowTallerUnderAColumnCap() {
        let busy = TimelineYears.grid(count: 20, rows: 1, maxColumns: 5, fill: .across)
        XCTAssertEqual(busy.count, 5, "five columns")
        XCTAssertEqual(busy.map(\.count), [4, 4, 4, 4, 4], "four rows tall")
        XCTAssertEqual(busy[0], [0, 5, 10, 15], "reading across each row")
        XCTAssertEqual(TimelineYears.grid(count: 1, rows: 1, maxColumns: 5, fill: .across), [[0]], "a quiet year shrinks to fit")
        XCTAssertEqual(TimelineYears.grid(count: 7, rows: 1, maxColumns: 5, fill: .across).map(\.count), [2, 2, 1, 1, 1],
                       "rows fill to the cap: 0 1 2 3 4 / 5 6")
        XCTAssertEqual(TimelineYears.grid(count: 7, rows: 1, maxColumns: 5, fill: .down), [[0, 1], [2, 3], [4, 5], [6]])
        XCTAssertTrue(TimelineYears.grid(count: 0, rows: 1, maxColumns: 5, fill: .across).isEmpty)
    }

    func testTimelineGrowthSettings() throws {
        var look = try JSONDecoder().decode(ElementAppearance.self, from: Data(#"{"layout":"timeline"}"#.utf8))
        XCTAssertNil(look.timelineMaxColumns, "same height by default")
        look.timelineGrowth = .taller
        XCTAssertEqual(look.timelineMaxColumns, 5, "five columns unless set")
        look.timelineColumns = 99
        XCTAssertEqual(look.timelineMaxColumns, ElementAppearance.timelineColumnRange.upperBound)
        look.timelineColumns = 1
        XCTAssertFalse(look.fillApplies, "one column: fill can't matter")
    }

    // MARK: Cover Flow

    func testCoverFlowCentreFacesForwardOnTop() {
        let centre = CoverFlowGeometry.place(distance: 0, side: 200)
        XCTAssertEqual(centre.x, 0)
        XCTAssertEqual(centre.rotation, 0)
        XCTAssertGreaterThan(centre.scale, 1)
        for d in 1...6 { XCTAssertGreaterThan(centre.zIndex, CoverFlowGeometry.place(distance: d, side: 200).zIndex) }
    }

    func testCoverFlowSidesMirror() {
        for d in 1...6 {
            let left = CoverFlowGeometry.place(distance: -d, side: 200), right = CoverFlowGeometry.place(distance: d, side: 200)
            XCTAssertEqual(left.x, -right.x, accuracy: 0.001)
            XCTAssertEqual(left.rotation, -right.rotation)
            XCTAssertEqual(left.zIndex, right.zIndex)
        }
    }

    func testCoverFlowGapAfterTheCentreThenPacked() {
        let first = CoverFlowGeometry.place(distance: 1, side: 200).x
        let second = CoverFlowGeometry.place(distance: 2, side: 200).x
        XCTAssertGreaterThan(first, second - first, "a wider gap beside the centre than between the rest")
    }

    func testCoverFlowDrawsOnlyNearTheCentre() {
        XCTAssertTrue(CoverFlowGeometry.isVisible(distance: CoverFlowGeometry.reach))
        XCTAssertFalse(CoverFlowGeometry.isVisible(distance: CoverFlowGeometry.reach + 1))
    }

    func testCoverFlowSizesAndSpacing() {
        XCTAssertLessThan(CoverFlowGeometry.side(for: .small), CoverFlowGeometry.side(for: .medium))
        XCTAssertLessThan(CoverFlowGeometry.side(for: .medium), CoverFlowGeometry.side(for: .large))
        let tight = CoverFlowGeometry.place(distance: 3, side: 200, spread: CoverFlowGeometry.spread(for: .compact)).x
        let loose = CoverFlowGeometry.place(distance: 3, side: 200, spread: CoverFlowGeometry.spread(for: .roomy)).x
        XCTAssertLessThan(tight, loose, "roomy spreads the side covers further")
        XCTAssertGreaterThan(CoverFlowGeometry.stageHeight(side: 200), 200 * 1.3, "room for the turned covers' near edges")
    }

    func testCoverFlowDrawsBeyondWhatsVisibleSoCoversArriveOffStage() {
        XCTAssertGreaterThan(CoverFlowGeometry.drawReach, CoverFlowGeometry.reach)
        XCTAssertEqual(CoverFlowGeometry.place(distance: 0, side: 200).brightness, 0)
        XCTAssertLessThan(CoverFlowGeometry.place(distance: 3, side: 200).brightness, 0, "side covers sit darker")
    }

    // MARK: Settings

    func testOnlyAlbumsGetTheNewLayouts() {
        XCTAssertTrue(ElementAppearance.layouts(for: .albums).contains(.coverFlow))
        XCTAssertTrue(ElementAppearance.layouts(for: .albums).contains(.timeline))
        for kind in [ResultKind.songs, .artists, .genres] {
            XCTAssertFalse(ElementAppearance.layouts(for: kind).contains(.coverFlow))
            XCTAssertFalse(ElementAppearance.layouts(for: kind).contains(.timeline))
        }
    }

    func testTimelineOrderDefaultsToOldestFirst() throws {
        let decoded = try JSONDecoder().decode(ElementAppearance.self, from: Data(#"{"layout":"timeline"}"#.utf8))
        XCTAssertEqual(decoded.layout, .timeline)
        XCTAssertNil(decoded.timelineOrder)
        XCTAssertEqual(ElementAppearance.rowRange(layout: .coverFlow, output: .albums), 1...1)
    }
}
