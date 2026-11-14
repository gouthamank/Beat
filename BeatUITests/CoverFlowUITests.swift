import AppKit
import XCTest

/// Cover Flow on the Mac, checked from a screenshot. The unit tests' snapshots draw the layer tree, which leaves out
/// its 3D (their Mac Cover Flow test is skipped); XCUITest's screenshots come from the window server, as on screen.
final class CoverFlowUITests: BeatUITestCase {
    func testCoverFlowLooksAsBefore() {
        launch(pinnedLook: true)
        createPage("Covers")
        waitFor("page.addElement").click()
        let name = waitFor("editor.name")
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Cover Flow")
        waitFor("editor.find").radioButtons["Albums"].click()
        waitFor("editor.tab").radioButtons["Appearance"].click()
        waitFor("editor.layout").radioButtons["Cover Flow"].click()
        waitFor("editor.save").click()
        XCTAssertTrue(element("editor.name").waitForNonExistence(timeout: 5), "the editor closed")
        let coverFlow = waitFor("coverFlow"), page = waitFor("page.Covers")
        // Each screenshot is checked even when an earlier one didn't match, so one run records all three.
        continueAfterFailure = true

        // The first album in front: the rest fan out to the right.
        ScreenshotReference.assertMatches(settledScreenshot(of: coverFlow, within: page), named: "mac-start")
        let first = caption(coverFlow)
        XCTAssertFalse(first.isEmpty, "the caption under the centre cover can be read")

        // The cover beside the centre comes forward when clicked, and Cover Flow takes the keyboard; → does the rest,
        // one cover at a time, each checked: presses sent straight after the click were lost.
        let beside = page.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: page.frame.width / 2 + 200, dy: coverFlow.frame.minY - page.frame.minY + 150))
        beside.click()
        eventually("the cover beside the centre came to the front") { caption(coverFlow) != first }
        for step in 2...4 {
            XCTAssertTrue(flipForward(coverFlow), "→ brought album \(step + 1) to the front (still \(caption(coverFlow)))")
        }
        ScreenshotReference.assertMatches(settledScreenshot(of: coverFlow, within: page), named: "mac-middle")

        // To the last album: → until it changes nothing.
        var flips = 0
        while flipForward(coverFlow), flips < 20 { flips += 1 }
        XCTAssertEqual(flips, 4, "nine albums: four more after the fifth")
        ScreenshotReference.assertMatches(settledScreenshot(of: coverFlow, within: page), named: "mac-end")
    }

    /// Presses → until another album comes to the front, up to three times (a press can be lost while Cover Flow takes
    /// the keyboard); false when none does, at the end.
    private func flipForward(_ coverFlow: XCUIElement) -> Bool {
        let before = caption(coverFlow)
        for _ in 0..<3 {
            app.typeKey(.rightArrow, modifierFlags: [])
            let deadline = Date().addingTimeInterval(0.8)
            while Date() < deadline {
                if caption(coverFlow) != before { return true }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
        }
        return false
    }

    /// The album named under the centre cover. A Mac text's string is its accessibility value; its label is empty, so
    /// reading the label saw no change at all.
    private func caption(_ coverFlow: XCUIElement) -> String {
        let text = coverFlow.staticTexts["coverFlow.caption"].firstMatch
        return (text.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? text.label
    }

    /// The part of `page` that `element` covers, once two pictures in a row match (for up to 3 seconds): covers settle
    /// into place after the page appears, and one taken mid-move would never match again. Through the page because an
    /// element's own screenshot is its whole frame on screen, and Cover Flow's runs past the window, taking in
    /// whatever window was beside it.
    private func settledScreenshot(of element: XCUIElement, within page: XCUIElement) -> Data {
        func take() -> Data { crop(page.screenshot().pngRepresentation, from: page.frame, to: element.frame) }
        var last = take()
        for _ in 0..<15 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            let next = take()
            if next == last { break }
            last = next
        }
        return last
    }

    /// `png`, a picture of `area`, cut down to `target`'s rows (both in screen points), across the area's full width:
    /// Cover Flow's frame starts partway into the page column, and cropping to it cut off the column's left side.
    private func crop(_ png: Data, from area: CGRect, to target: CGRect) -> Data {
        guard let image = NSBitmapImageRep(data: png)?.cgImage else { return png }
        let scale = CGFloat(image.width) / area.width
        let rows = area.intersection(target)
        let visible = CGRect(x: area.minX, y: rows.minY, width: area.width, height: rows.height)
        let rect = CGRect(x: (visible.minX - area.minX) * scale, y: (visible.minY - area.minY) * scale,
                          width: visible.width * scale, height: visible.height * scale).integral
        guard let cropped = image.cropping(to: rect) else { return png }
        return NSBitmapImageRep(cgImage: cropped).representation(using: .png, properties: [:]) ?? png
    }
}
