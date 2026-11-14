import XCTest

/// Making and changing pages and their elements.
final class PageUITests: BeatUITestCase {
    /// A new page (⌘N) named `name`. The name sheet selects the placeholder, so typing replaces it.
    @discardableResult
    private func createPage(_ name: String) -> XCUIElement {
        app.typeKey("n", modifierFlags: .command)
        waitFor("nameSheet.name").typeText(name)
        waitFor("nameSheet.save").click()
        return waitFor("sidebar.page.\(name)")
    }

    /// Picks `item` from the element's right-click menu.
    private func menu(_ element: XCUIElement, _ item: String) {
        element.rightClick()
        let entry = app.menuItems[item].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 5), "\(item) in the menu")
        entry.click()
    }

    func testCreatingRenamingAndDeletingAPage() {
        launch()
        let page = createPage("Road Trip")

        menu(page, "Rename…")
        let field = waitFor("nameSheet.name")
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Long Drive")
        waitFor("nameSheet.save").click()
        let renamed = waitFor("sidebar.page.Long Drive")
        XCTAssertFalse(element("sidebar.page.Road Trip").exists, "renamed, not copied")

        menu(renamed, "Delete…")
        // In the window (the confirmation is a sheet on it): the app-wide query found the Touch Bar's copy first.
        let confirm = app.windows.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "deleting asks first")
        confirm.click()
        XCTAssertTrue(element("sidebar.page.Long Drive").waitForNonExistence(timeout: 5))
    }

    /// Each test starts with only Home: Beat's stores once loaded their files before the fresh start ran, and the
    /// last test's pages came back.
    func testAFreshStartForgetsTheLastLaunchsPages() {
        launch()
        createPage("Leftover")
        quit()
        launch()
        waitFor("sidebar.page.Home")
        XCTAssertFalse(element("sidebar.page.Leftover").exists, "a fresh start has only Home")
    }

    func testCancellingANewPageLeavesNothingBehind() {
        launch()
        app.typeKey("n", modifierFlags: .command)
        waitFor("nameSheet.name")
        waitFor("nameSheet.cancel").click()
        XCTAssertTrue(element("nameSheet.name").waitForNonExistence(timeout: 5))
        XCTAssertFalse(element("sidebar.page.New Page").exists, "the page made for naming is gone again")
    }

    func testAddingAnElementShowsItOnThePage() {
        launch()
        createPage("Mixes")
        waitFor("page.addElement").click()
        let name = waitFor("editor.name")
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Everything")
        waitFor("editor.save").click()
        waitFor("element.Everything")
        XCTAssertFalse(app.staticTexts["No matches"].exists, "it found songs in the library")
    }

    func testCancellingANewElementLeavesNothingBehind() {
        launch()
        createPage("Mixes")
        waitFor("page.addElement").click()
        waitFor("editor.name")
        waitFor("editor.cancel").click()
        XCTAssertTrue(element("editor.name").waitForNonExistence(timeout: 5))
        XCTAssertFalse(element("element.New Smart Filter").exists, "no element was added")
    }
}
