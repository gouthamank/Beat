import XCTest

/// Moving around on a phone: the sidebar drawer, album pages, Now Playing.
final class NavigationUITests: BeatiOSUITestCase {
    func testTheDrawerOpensAPageAndGetsOutOfTheWay() {
        launch()
        openFromSidebar("sidebar.library.albums")
        waitFor("albumTile.First Light")
        // Closed, the drawer's sidebar leaves the window (its navigation stack would answer for the status bar).
        XCTAssertTrue(element("sidebar.library.albums").waitForNonExistence(timeout: 5), "the drawer closed over the page it opened")
    }

    func testOpeningAnAlbumAndSwipingBack() {
        launch()
        openAlbum("First Light")
        swipeBack()
        XCTAssertTrue(element("albumPage").waitForNonExistence(timeout: 5), "the swipe went back")
        waitFor("albumTile.First Light")
    }

    func testNowPlayingOpensFromTheBarAndPullsDownToClose() {
        launch()
        playAlbum("First Light")
        // The bar's left part (cover and title): its right end holds the play and next buttons.
        element("nowPlayingBar").coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        let nowPlaying = waitFor("nowPlaying")
        let top = nowPlaying.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        top.press(forDuration: 0.05, thenDragTo: nowPlaying.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        XCTAssertTrue(element("nowPlaying").waitForNonExistence(timeout: 5), "pulled down, it closed")
        XCTAssertTrue(element("nowPlayingBar").exists, "back into the bar, still playing")
    }

    func testSwipingSidewaysInNowPlayingChangesTheSong() {
        launch()
        // Five songs, paused at once: the fixture songs last two seconds, and played on, an album ran out under the
        // swipes (Now Playing closes past the last song).
        playAlbum("Tin and Copper")
        let pause = element("nowPlayingBar").buttons["Pause"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 5), "the bar's Pause")
        pause.tap()
        element("nowPlayingBar").coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5)).tap()
        waitFor("nowPlaying")
        let title = waitFor("nowPlaying.title")
        let first = title.label

        // Across the cover, right to left: the next song.
        swipe(from: 0.85, to: 0.15)
        XCTAssertTrue(eventually { title.label != first }, "a left swipe played the next song (still \(title.label))")
        let second = title.label

        // Back again, left to right: the one before.
        swipe(from: 0.15, to: 0.85)
        XCTAssertTrue(eventually { title.label == first }, "a right swipe went back to \(first) (from \(second), now \(title.label))")
    }

    func testSongsKeepsItsPlaceAfterAnAlbum() {
        launch()
        openFromSidebar("sidebar.library.songs")
        // Down to Cobalt's albums, past Aurora Lane's and Bronze Era's.
        let pigment = element("songs.album.Pigment")
        // Short drags: a whole swipe could carry it past the top of the screen.
        for _ in 0..<15 where !(pigment.exists && pigment.isHittable) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
        }
        XCTAssertTrue(pigment.isHittable, "scrolled down to Pigment")
        XCTAssertFalse(element("songs.album.First Light").isHittable, "the top of the list is out of sight")

        tap("songs.album.Pigment")
        waitFor("albumPage")
        swipeBack()
        XCTAssertTrue(element("albumPage").waitForNonExistence(timeout: 5), "back to Songs")
        XCTAssertTrue(eventually { pigment.isHittable }, "still where it was, at Pigment")
        XCTAssertFalse(element("songs.album.First Light").isHittable, "not back at the top")
    }

    /// A sideways drag across the cover, between two fractions of the screen's width. On the screen, not on Now
    /// Playing itself, which is rebuilt as the next song's art settles in: a query for it then found nothing.
    private func swipe(from start: CGFloat, to end: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: start, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: end, dy: 0.35)))
    }
}
