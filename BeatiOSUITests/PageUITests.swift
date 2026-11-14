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
        // Closed, the drawer's sidebar leaves the window (its navigation stack would answer for the status bar).
        XCTAssertTrue(element("sidebar.page.Road Trip").waitForNonExistence(timeout: 5), "the drawer closed over the new page")
        tap("sidebar.open")
        waitFor("sidebar.page.Road Trip")
    }
}
