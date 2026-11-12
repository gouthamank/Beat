import XCTest
@testable import Beat

final class ArtworkPaletteTests: XCTestCase {
    private func gray(_ v: Double) -> RGB { RGB(r: v, g: v, b: v) }

    /// A cover made of colour areas: each entry is (colour, pixel count).
    private func pixels(_ areas: [(RGB, Int)]) -> [(color: RGB, weight: Double)] {
        areas.flatMap { color, count in Array(repeating: (color: color, weight: 1.0), count: count) }
    }

    func testContrastMatchesWCAG() {
        XCTAssertEqual(RGB.black.contrast(with: .white), 21, accuracy: 0.01)
        XCTAssertEqual(RGB.white.contrast(with: .white), 1, accuracy: 0.001)
        // #777777 on white is the classic 4.48:1, just under AA.
        XCTAssertEqual(gray(0x77 / 255).contrast(with: .white), 4.48, accuracy: 0.02)
    }

    func testDominantColourBecomesBackgroundAndSecondColourTheText() {
        let navy = RGB(r: 0.05, g: 0.08, b: 0.3)
        let gold = RGB(r: 0.95, g: 0.8, b: 0.3)
        let palette = ArtworkPalette.make(pixels: pixels([(navy, 400), (gold, 120)]))
        XCTAssertLessThan(palette.background.distance(to: navy), 0.05)
        XCTAssertLessThan(palette.primary.distance(to: gold), 0.05)
        XCTAssertTrue(palette.isDark)
    }

    func testLowContrastCoverFallsBackToWhiteOrBlack() {
        let palette = ArtworkPalette.make(pixels: pixels([(gray(0.45), 400), (gray(0.55), 100)]))
        XCTAssertTrue(palette.primary == .white || palette.primary == .black)
        XCTAssertGreaterThanOrEqual(palette.primary.contrast(with: palette.background), ArtworkPalette.primaryContrast)
    }

    func testLightCoverIsNotDark() {
        let palette = ArtworkPalette.make(pixels: pixels([(RGB(r: 0.96, g: 0.94, b: 0.88), 500), (RGB(r: 0.6, g: 0.1, b: 0.1), 80)]))
        XCTAssertFalse(palette.isDark)
    }

    func testChosenTextAlwaysMeetsMinimumContrast() {
        var rng = SeededRNG(seed: 11)
        for _ in 0..<200 {
            func random() -> RGB { RGB(r: Double.random(in: 0...1, using: &rng), g: Double.random(in: 0...1, using: &rng), b: Double.random(in: 0...1, using: &rng)) }
            let areas = (0..<4).map { _ in (random(), Int.random(in: 10...300, using: &rng)) }
            let palette = ArtworkPalette.make(pixels: pixels(areas))
            XCTAssertGreaterThanOrEqual(palette.primary.contrast(with: palette.background), ArtworkPalette.primaryContrast)
            XCTAssertGreaterThanOrEqual(palette.secondary.contrast(with: palette.background), ArtworkPalette.secondaryContrast)
        }
    }

    func testShadesOfOneColourClusterTogether() {
        let reds = (0..<5).map { RGB(r: 0.7 + Double($0) * 0.02, g: 0.1, b: 0.1) }
        let clusters = ArtworkPalette.cluster(pixels(reds.map { ($0, 50) } + [(RGB.white, 100)]))
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters.first?.weight, 250, "the reds together outweigh the white")
    }

    func testEmptyCoverStillGivesReadablePalette() {
        let palette = ArtworkPalette.make(pixels: [])
        XCTAssertGreaterThanOrEqual(palette.primary.contrast(with: palette.background), ArtworkPalette.primaryContrast)
    }

    // MARK: Visualizer scene colours

    func testSceneColoursKeepCoverColoursThatShowOnDark() {
        let red = RGB(r: 0.9, g: 0.3, b: 0.2), yellow = RGB(r: 1, g: 0.9, b: 0.4)
        let colours = SceneColours(palette: ArtworkPalette(background: gray(0.1), primary: red, secondary: yellow))
        XCTAssertEqual(colours.accent, red)
        XCTAssertEqual(colours.light, yellow)
        XCTAssertLessThan(colours.deep.contrast(with: .black), gray(0.1).contrast(with: .black) + 0.01)
    }

    func testSceneColoursLightenCoverColoursTooDarkForTheGround() {
        // A light cover: its text colours are dark and would vanish on the scenes' dark ground.
        let colours = SceneColours(palette: ArtworkPalette(background: gray(0.95), primary: gray(0.1), secondary: gray(0.25)))
        XCTAssertGreaterThanOrEqual(colours.accent.contrast(with: .black), 3)
        XCTAssertGreaterThanOrEqual(colours.light.contrast(with: .black), 3)
    }

    func testSceneColoursWithoutCover() {
        let colours = SceneColours(palette: nil)
        XCTAssertGreaterThanOrEqual(colours.accent.contrast(with: .black), 3)
        XCTAssertLessThan(colours.deep.contrast(with: .black), 1.5)
    }
}
