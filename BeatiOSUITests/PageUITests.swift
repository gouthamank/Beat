import XCTest

/// Making pages on a phone.
final class PageUITests: BeatiOSUITestCase {
    /// A new page is what you'll edit next, so the drawer closes on it once named (1.1.3).
    func testANewPageClosesTheDrawerOnIt() {
        launch()
        tap("sidebar.open")
        tap("sidebar.new")
        let newPage = app.buttons["New Page"].firstMatch
        XCTAssertTrue(newPage.waitForExistence(timeout: 5), "the New menu offers New Page")
        newPage.tap()
        // The name sheet selects the placeholder, so typing replaces it.
        waitFor("nameSheet.name").typeText("Road Trip")
        tap("nameSheet.save")

        waitFor("page.addElement")
        XCTAssertTrue(eventually { !self.element("sidebar.page.Road Trip").isHittable }, "the drawer closed over the new page")
        XCTAssertTrue(element("sidebar.page.Road Trip").exists, "and it's in the sidebar")
    }
}
