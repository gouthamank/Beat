import XCTest
@testable import Beat

/// The one-line rows of the phone's rules form (`RulesForm`).
@MainActor
final class RuleSummaryTests: XCTestCase {
    private func summary(_ field: Field, _ op: RuleOperator, _ value: RuleValue) -> String {
        RuleSummary.text(Rule(field: field, op: op, value: value))
    }

    func testRules() {
        XCTAssertEqual(summary(.artist, .contains, .text("Bach")), "Artist contains “Bach”")
        XCTAssertEqual(summary(.artist, .contains, .text("")), "Artist contains …", "a value still to fill in")
        XCTAssertEqual(summary(.rating, .greaterThan, .number(3)), "Rating (Stars) is greater than ★★★")
        XCTAssertEqual(summary(.year, .is, .number(2011)), "Year is 2011", "no thousands separator in a year")
        XCTAssertEqual(summary(.year, .inRange, .range(1990, 1999)), "Year is in the range 1990–1999")
        XCTAssertEqual(summary(.dateAdded, .inLast, .relative(2, .weeks)), "Date Added is in the last 2 weeks")
        XCTAssertEqual(summary(.compilation, .isTrue, .none), "Compilation is true")
    }

    func testGroups() {
        XCTAssertEqual(RuleSummary.groupTitle(EditGroup(match: .all)), "Group: all of")
        XCTAssertEqual(RuleSummary.groupTitle(EditGroup(match: .any)), "Group: any of")
        XCTAssertEqual(RuleSummary.groupTitle(EditGroup(match: .none)), "Group: none of")
    }

    func testSortKeys() {
        XCTAssertEqual(RuleSummary.text(SortKey(field: .field(.artist), ascending: true)), "Artist, a to z")
        XCTAssertEqual(RuleSummary.text(SortKey(field: .field(.dateAdded), ascending: false)), "Date Added, newest first")
        XCTAssertEqual(RuleSummary.text(SortKey(field: .field(.playCount), ascending: false)), "Plays, highest first")
        XCTAssertEqual(RuleSummary.text(SortKey(field: .random, ascending: true)), "Random", "no direction")
    }
}
