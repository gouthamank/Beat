import XCTest
@testable import Beat

final class NewElementDefaultsTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suiteName = "BeatTests.NewElementDefaults.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func content(_ element: PageElement) -> PageElement {
        var copy = element
        copy.filter.id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        return copy
    }

    func testNothingSavedGivesBuiltIn() {
        XCTAssertNil(NewElementDefaults.saved(in: defaults))
        let element = NewElementDefaults.current(in: defaults, customFields: [])
        XCTAssertEqual(content(element), content(NewElementDefaults.builtIn))
    }

    func testSavedDefaultsComeBackWithFreshIDs() {
        var custom = NewElementDefaults.builtIn
        custom.filter.name = "Recent Albums"
        custom.filter.output = .albums
        custom.appearance.layout = .grid
        custom.appearance.rows = 3
        NewElementDefaults.save(custom, to: defaults)

        let first = NewElementDefaults.current(in: defaults, customFields: [])
        let second = NewElementDefaults.current(in: defaults, customFields: [])
        XCTAssertEqual(content(first), content(custom))
        XCTAssertNotEqual(first.id, custom.id)
        XCTAssertNotEqual(first.id, second.id, "every new element is its own")
    }

    func testUnreadableDataFallsBackToBuiltIn() {
        defaults.set(Data("not json".utf8), forKey: NewElementDefaults.key)
        XCTAssertNil(NewElementDefaults.saved(in: defaults))
        XCTAssertEqual(content(NewElementDefaults.current(in: defaults, customFields: [])), content(NewElementDefaults.builtIn))
    }

    func testResetClears() {
        NewElementDefaults.save(NewElementDefaults.builtIn, to: defaults)
        XCTAssertNotNil(NewElementDefaults.saved(in: defaults))
        NewElementDefaults.reset(in: defaults)
        XCTAssertNil(NewElementDefaults.saved(in: defaults))
    }

    func testSummary() {
        var element = NewElementDefaults.builtIn
        element.appearance.layout = .grid
        element.appearance.rows = 2
        XCTAssertEqual(NewElementDefaults.summary(element), "Songs · 1 rule · Grid, 2 rows")
        element.appearance.rows = ElementAppearance.allRows
        XCTAssertEqual(NewElementDefaults.summary(element), "Songs · 1 rule · Grid, all rows")
    }
}
