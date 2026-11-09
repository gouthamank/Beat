import XCTest
@testable import Beat

final class CustomFieldTests: XCTestCase {
    private func field(_ extraction: CustomField.Extraction, source: Field = .album) -> CustomField {
        CustomField(name: "Cat", source: source, extraction: extraction)
    }

    private func value(_ extraction: CustomField.Extraction, album: String) -> String? {
        field(extraction).value(for: .fixture(id: 1, album: album))
    }

    func testLastParentheses() {
        XCTAssertEqual(value(.lastParentheses, album: "Certainties EP (AUX002)"), "AUX002")
        XCTAssertEqual(value(.lastParentheses, album: "Remixes (Part 2) (AUXCD004)"), "AUXCD004", "uses the last pair")
        XCTAssertEqual(value(.lastParentheses, album: "Spaced ( AUX010 )"), "AUX010", "trims spaces")
        XCTAssertNil(value(.lastParentheses, album: "No Catalog"))
        XCTAssertNil(value(.lastParentheses, album: "Empty ()"))
    }

    func testLastBrackets() {
        XCTAssertEqual(value(.lastBrackets, album: "Album [AUXLP003]"), "AUXLP003")
        XCTAssertNil(value(.lastBrackets, album: "Album (AUX001)"))
    }

    func testPatternWholeMatchAndCaptureGroup() {
        XCTAssertEqual(value(.pattern(#"AUX\w+"#), album: "77 EP (AUX007)"), "AUX007")
        XCTAssertEqual(value(.pattern(#"AUX(?:CD|LP)?(\d+)"#), album: "Memory Fields (AUXCD002)"), "002")
        XCTAssertEqual(value(.pattern(#"aux\d+"#), album: "Album (AUX5)"), "AUX5", "case doesn't matter")
        XCTAssertNil(value(.pattern(#"AUX\d+"#), album: "Other Label (ASC001)"))
    }

    func testInvalidOrEmptyPatternMatchesNothing() {
        XCTAssertFalse(field(.pattern("AUX(")).isValid)
        XCTAssertNil(value(.pattern("AUX("), album: "Album (AUX001)"))
        XCTAssertFalse(field(.pattern("")).isValid)
        XCTAssertNil(value(.pattern(""), album: "Album (AUX001)"))
        XCTAssertTrue(field(.lastParentheses).isValid)
    }

    func testOtherSourceFields() {
        var track = Track.fixture(id: 1, album: "Album (AUX1)")
        track.comments = "Cat (C-9)"
        XCTAssertEqual(field(.lastParentheses, source: .comments).value(for: track), "C-9")
    }

    // MARK: Sorting

    private func albums(_ titles: [String]) -> PreparedLibrary {
        let tracks = titles.enumerated().map { i, title in
            Track.fixture(id: PersistentID(i + 1), album: title, albumID: PersistentID(100 + i))
        }
        return PreparedLibrary(snapshot: .build(tracks: tracks))
    }

    private func sortedTitles(_ lib: PreparedLibrary, ascending: Bool) -> [String] {
        let key = SortKey(field: .custom(field(.lastParentheses)), ascending: ascending)
        let filter = SmartFilter(id: UUID(), name: "T", output: .albums, steps: [.sort([key])])
        return SmartFilterEngine.evaluate(filter, in: lib).albums.map(\.title)
    }

    func testSortsCatalogNumbersNaturally() {
        let lib = albums(["Ten (AUX10)", "Two (AUX2)", "One (AUX1)"])
        XCTAssertEqual(sortedTitles(lib, ascending: true), ["One (AUX1)", "Two (AUX2)", "Ten (AUX10)"])
        XCTAssertEqual(sortedTitles(lib, ascending: false), ["Ten (AUX10)", "Two (AUX2)", "One (AUX1)"])
    }

    func testUnmatchedSortLastInBothDirections() {
        let lib = albums(["No Number", "Two (AUX2)", "One (AUX1)"])
        XCTAssertEqual(sortedTitles(lib, ascending: true).last, "No Number")
        XCTAssertEqual(sortedTitles(lib, ascending: false).last, "No Number")
    }

    // MARK: Refreshing embedded copies

    func testRefreshReplacesOnlyMatchingID() {
        let old = field(.lastParentheses)
        var updated = old
        updated.extraction = .lastBrackets
        let other = field(.lastParentheses)

        var filter = SmartFilter(id: UUID(), name: "T", steps: [
            .sort([SortKey(field: .custom(old), ascending: true), SortKey(field: .custom(other), ascending: true)]),
        ])
        filter.refreshCustomFields([updated])
        guard case .sort(let keys) = filter.steps[0] else { return XCTFail() }
        XCTAssertEqual(keys[0].field, .custom(updated))
        XCTAssertEqual(keys[1].field, .custom(other), "a field not in the list keeps its copy")
    }
}
