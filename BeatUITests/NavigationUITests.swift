import XCTest

/// Moving around: album pages, sidebar pages, Now Playing.
final class NavigationUITests: BeatUITestCase {
    func testOpeningAnAlbumAndGoingBack() {
        launch()
        openAlbum("First Light")
        app.typeKey("[", modifierFlags: .command)
        XCTAssertTrue(element("albumPage").waitForNonExistence(timeout: 5), "⌘[ closed the album page")
        waitFor("albumTile.First Light")
    }

    func testEachSidebarPageKeepsItsPlace() {
        launch()
        openAlbum("First Light")
        waitFor("sidebar.library.artists").click()
        XCTAssertTrue(element("albumPage").waitForNonExistence(timeout: 5), "another sidebar page shows its own top level")
        waitFor("sidebar.library.albums").click()
        waitFor("albumPage")
    }

    func testNowPlayingOpensFromTheBarAndClosesWithEscape() {
        launch()
        playAlbum("First Light")
        // The bar's left end (cover and title): its middle holds the transport buttons.
        element("nowPlayingBar").coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).click()
        waitFor("nowPlaying")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(element("nowPlaying").waitForNonExistence(timeout: 5), "Esc closed Now Playing")
        XCTAssertTrue(element("nowPlayingBar").exists, "back into the bar, still playing")
    }
}
