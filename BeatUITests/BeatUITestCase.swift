import XCTest

/// A UI test of Beat: launches the UI-test build (its own bundle ID, so its own settings) on the fixture songs in
/// `Fixtures/Library`, with its files in a temporary home for this test. The app refuses to start any other way
/// (`LaunchOptions.checkIsolation`), so a test can't reach the user's library, pages or settings.
///
/// The home is /tmp/BeatUITests, made by `make mac-test-ui` before any launch: it has to exist when Beat starts (a home
/// made later left settings unable to see the system's, and nothing saved stuck), and this runner is sandboxed, so
/// it can't make it there itself; its own temporary folder is inside its container, where Beat keeping files made
/// macOS ask whether it may access another app's data. Tests share it; each starts fresh (`-BeatFreshStart`).
@MainActor
class BeatUITestCase: XCTestCase {
    var app: XCUIApplication!
    private let home = "/tmp/BeatUITests"

    static let fixtureLibrary = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Library", isDirectory: true)

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        if let app, app.state != .notRunning { app.terminate() }
    }

    /// Launches Beat, fresh: no settings and no files from earlier tests. `freshSettings: false` keeps what the last
    /// launch in this test saved (window size, selection, pages).
    /// Every launch saves and restores windows as one from the Dock does (XCTest otherwise adds
    /// `-ApplePersistenceIgnoreState YES`). `pinnedLook` sets dark mode and the blue accent for this launch, whatever
    /// the Mac's own, for tests that compare screenshots.
    func launch(freshSettings: Bool = true, pinnedLook: Bool = false) {
        app = XCUIApplication()
        app.launchEnvironment["CFFIXED_USER_HOME"] = home
        app.launchArguments = ["-BeatFixtureLibrary", Self.fixtureLibrary.path, "-ApplePersistenceIgnoreState", "NO"]
            // With a value: AppKit reads `-name value` pairs, and a bare flag followed by another argument left that one's
            // value over, which it took for a file to open, so no window was made.
            + (freshSettings ? ["-BeatFreshStart", "YES"] : [])
            + (pinnedLook ? ["-AppleInterfaceStyle", "Dark", "-AppleAccentColor", "4"] : [])
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10), "Beat opened a window")
    }

    /// Quits with ⌘Q, as a person would, so Beat saves what it saves on the way out.
    func quit() {
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10), "Beat quit")
    }

    /// The element with this accessibility identifier, whatever its type.
    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// Waits for the element and returns it, failing the test if it never appears.
    @discardableResult
    func waitFor(_ identifier: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let found = element(identifier)
        XCTAssertTrue(found.waitForExistence(timeout: timeout), "\(identifier) appeared", file: file, line: line)
        return found
    }

    /// Waits until `condition` holds, for UI that settles after an animation or a measurement; fails after `timeout`.
    func eventually(_ message: @autoclosure () -> String, timeout: TimeInterval = 5, file: StaticString = #filePath,
                    line: UInt = #line, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(condition(), message(), file: file, line: line)
    }

    // MARK: Common steps

    /// A new page (⌘N) named `name`. The name sheet selects the placeholder, so typing replaces it.
    @discardableResult
    func createPage(_ name: String) -> XCUIElement {
        app.typeKey("n", modifierFlags: .command)
        waitFor("nameSheet.name").typeText(name)
        waitFor("nameSheet.save").click()
        return waitFor("sidebar.page.\(name)")
    }

    /// Library ▸ Albums, then an album's page. The grid is lazy, so only tiles on screen exist: use albums near the
    /// top (sorted by artist: Aurora Lane's First Light, Northern Lights and Low Sun come first).
    func openAlbum(_ title: String) {
        waitFor("sidebar.library.albums").click()
        waitFor("albumTile.\(title)").click()
        waitFor("albumPage")
    }

    /// Plays an album from its page, so the now-playing bar shows.
    func playAlbum(_ title: String) {
        openAlbum(title)
        waitFor("albumPage.play").click()
        waitFor("nowPlayingBar")
    }

    /// Drags the window's bottom-right corner by `offset` (negative is smaller), and fails if the size didn't change,
    /// so a drag that missed the corner can't let a test pass without testing anything.
    func resizeWindow(by offset: CGVector, file: StaticString = #filePath, line: UInt = #line) {
        let window = app.windows.firstMatch
        let before = window.frame.size
        let corner = window.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 1)).withOffset(CGVector(dx: -3, dy: -3))
        corner.press(forDuration: 0.3, thenDragTo: corner.withOffset(offset))
        eventually("the window resized from \(before) (now \(window.frame.size))", file: file, line: line) {
            window.frame.size != before
        }
    }
}
