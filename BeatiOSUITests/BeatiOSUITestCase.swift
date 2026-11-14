import XCTest

/// A UI test of Beat on the iPhone Simulator: launches the UI-test build on the fixture songs in `Fixtures/Library`. On
/// the Simulator that build is its own app (`dev.gouthaman.Beat.uitest`), with its own container, so it never sees the
/// songs, pages or settings of the Beat you run there; each test starts fresh (`-BeatFreshStart YES`, which clears
/// that container's files and settings). The app refuses to start otherwise (`LaunchOptions.checkIsolation`).
@MainActor
class BeatiOSUITestCase: XCTestCase {
    var app: XCUIApplication!

    static let fixtureLibrary = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Library", isDirectory: true)

    override func setUp() async throws {
        continueAfterFailure = false
    }

    override func tearDown() async throws {
        if let app, app.state != .notRunning { app.terminate() }
    }

    /// Launches Beat, fresh. `freshStart: false` keeps what the last launch in this test saved.
    func launch(freshStart: Bool = true) {
        app = XCUIApplication()
        // In pairs: a bare flag followed by another argument left that one's value over (see TESTING.md).
        app.launchArguments = ["-BeatFixtureLibrary", Self.fixtureLibrary.path] + (freshStart ? ["-BeatFreshStart", "YES"] : [])
        app.launch()
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

    /// Taps once the element can take it: things that slide in (the drawer) exist before they're tappable. Taps its
    /// centre if it never says so; the sidebar rows' identifier lands on their icon, which isn't a control itself.
    func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = waitFor(identifier, file: file, line: line)
        let deadline = Date().addingTimeInterval(3)
        while !target.isHittable, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        if target.isHittable {
            target.tap()
        } else {
            target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
    }

    /// Whether `condition` comes to hold within `timeout`, for UI that settles after an animation.
    func eventually(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    // MARK: Common steps

    /// Opens the sidebar drawer and picks a row in it.
    func openFromSidebar(_ identifier: String) {
        tap("sidebar.open")
        tap(identifier)
    }

    /// Library ▸ Albums, then an album's page. The grid is lazy: use albums near the top (First Light, Northern Lights,
    /// Low Sun, Tin and Copper). The fixture songs last two seconds: pause when a test needs one to stay.
    func openAlbum(_ title: String) {
        openFromSidebar("sidebar.library.albums")
        tap("albumTile.\(title)")
        waitFor("albumPage")
    }

    /// Plays an album from its page, so the now-playing bar shows.
    func playAlbum(_ title: String) {
        openAlbum(title)
        tap("albumPage.play")
        waitFor("nowPlayingBar")
    }

    /// A swipe in from the screen's left edge, as for going back.
    func swipeBack() {
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)))
    }
}
