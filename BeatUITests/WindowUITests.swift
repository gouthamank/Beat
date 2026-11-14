import XCTest

/// The window as a whole: the two regressions of 1.1.2, caught then only by hand.
final class WindowUITests: BeatUITestCase {
    /// The bar sits over the page column, centred and inside it, near the window's bottom (pages end above it: they
    /// leave room for it, `nowPlayingBarSpace`).
    private func assertBarOverPage(_ moment: String, file: StaticString = #filePath, line: UInt = #line) {
        let bar = element("nowPlayingBar"), page = element("albumPage"), window = app.windows.firstMatch
        eventually("the bar is centred over the page column \(moment): bar \(bar.frame), page \(page.frame)",
                   file: file, line: line) {
            abs(bar.frame.midX - page.frame.midX) <= 2
        }
        XCTAssertGreaterThanOrEqual(bar.frame.minX, page.frame.minX - 1, "inside the column \(moment)", file: file, line: line)
        XCTAssertLessThanOrEqual(bar.frame.maxX, page.frame.maxX + 1, "inside the column \(moment)", file: file, line: line)
        XCTAssertLessThanOrEqual(bar.frame.maxY, window.frame.maxY, "inside the window \(moment)", file: file, line: line)
        XCTAssertGreaterThan(bar.frame.maxY, window.frame.maxY - 60,
                             "near the window's bottom \(moment): bar \(bar.frame), window \(window.frame)", file: file, line: line)
    }

    func testTheNowPlayingBarFollowsTheWindowAsItResizes() {
        launch()
        playAlbum("First Light")
        assertBarOverPage("at first")

        // A fresh window opens at its smallest, so it grows first, then shrinks back down to the minimum.
        resizeWindow(by: CGVector(dx: 300, dy: 120))
        assertBarOverPage("after growing the window")

        resizeWindow(by: CGVector(dx: -400, dy: -200))
        assertBarOverPage("after shrinking it to its smallest")
    }

    func testTheWindowKeepsItsSizeAfterARelaunch() {
        launch()
        resizeWindow(by: CGVector(dx: 240, dy: 110))
        let resized = app.windows.firstMatch.frame
        // As a person would: the window's frame is saved after the resize, not during it.
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        quit()

        launch(freshSettings: false)
        let reopened = app.windows.firstMatch.frame
        XCTAssertEqual(reopened.width, resized.width, accuracy: 2, "width: resized \(resized), reopened \(reopened)")
        XCTAssertEqual(reopened.height, resized.height, accuracy: 2, "height: resized \(resized), reopened \(reopened)")
    }
}
