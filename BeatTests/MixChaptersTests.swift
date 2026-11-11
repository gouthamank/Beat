import XCTest
@testable import Beat

final class MixChaptersTests: XCTestCase {
    private func chapters(_ lrc: String) -> [MixChapter]? {
        LRC.parse(lrc).flatMap(MixChapters.from)
    }

    // MARK: Tracklists

    func testHourTracklistIsAMix() throws {
        let mix = """
            [0:00:00] Marginal - Springhead [CX Digital]
            [0:03:28] Mr Sizef & Unquote - Hours Have No Reverse Motion [Hospital]
            [0:06:31] Alister - Violence [DubKraft]
            [0:10:11] Molecular Structures - Bohemian Quarter
            [0:14:48] Pessimist - Whispers Of Scandal [Touched By]
            [1:35:57] Rockwell Feat. Stapleton - Patrol The Block
        """
        let found = try XCTUnwrap(chapters(mix))
        XCTAssertEqual(found.count, 6)
        XCTAssertEqual(found[1], MixChapter(start: 208, title: "Mr Sizef & Unquote - Hours Have No Reverse Motion [Hospital]"))
        XCTAssertEqual(MixChapters.chapter(at: 400, in: found)?.title, "Alister - Violence [DubKraft]")
    }

    func testNumberedTracklistWithUnknownTracksIsAMix() throws {
        let mix = """
        1. [00:00] Diazepam - Distances [Nerve Breaks - Free Release]
        2. [04:36] Muted - Empty Valley [Hidden Hawaii Digital]
        3. [06:51] ?
        4. [09:53] Genotype & Tobias A.M - Fatal Error
        5. [13:55] Muted - The Well [Manifesto]
        6. [15:54] Genotype - The Director [Ingredients]
        """
        let found = try XCTUnwrap(chapters(mix))
        XCTAssertEqual(found.map(\.title)[2], "?")
    }

    // MARK: Lyrics

    func testSongLyricsAreNotAMix() {
        let song = (0..<40).map { String(format: "[%02d:%02d.00]Line number %d of the song", ($0 * 5) / 60, ($0 * 5) % 60, $0) }
            .joined(separator: "\n")
        XCTAssertNil(chapters(song))
    }

    func testLongSparseSongIsNotAMix() {
        // 20 lines sung over three minutes, in a 13-minute track with long instrumental parts either side.
        let sung = (0..<20).map { 8 * 60 + 40 + $0 * 9 }
        let song = sung.map { String(format: "[%02d:%02d.00]Remember when you were young - you shone", $0 / 60, $0 % 60) }
            .joined(separator: "\n")
        XCTAssertNil(chapters(song), "even with dashes, lines seconds apart are lyrics")
    }

    func testFewSpreadOutLyricLinesAreNotAMix() {
        let song = "[01:00.00]Ooh\n[04:00.00]Far away\n[07:00.00]Across the sky\n[10:00.00]Ooh"
        XCTAssertNil(chapters(song), "minutes apart, but nothing reads like a tracklist")
    }

    func testFewerThanThreeLinesIsNotAMix() {
        XCTAssertNil(chapters("[00:00] A - One\n[05:00] B - Two"))
    }

    // MARK: Bar colour

    func testBarTintPicksTheColourfulOne() {
        let palette = ArtworkPalette(background: RGB(r: 0.1, g: 0.1, b: 0.1), primary: RGB(r: 0.9, g: 0.3, b: 0.2), secondary: .white)
        XCTAssertEqual(BarTint.color(for: palette), RGB(r: 0.9, g: 0.3, b: 0.2))
    }

    func testBarTintFallsBackForGreys() {
        let palette = ArtworkPalette(background: RGB(r: 0.1, g: 0.1, b: 0.1), primary: RGB(r: 0.9, g: 0.9, b: 0.88), secondary: .white)
        XCTAssertNil(BarTint.color(for: palette))
        XCTAssertNil(BarTint.color(for: nil))
    }

    func testReadableLightensDarkColoursInDarkMode() {
        let navy = RGB(r: 0.05, g: 0.08, b: 0.3)
        let result = BarTint.readable(navy, dark: true)
        XCTAssertNotEqual(result, navy)
        XCTAssertGreaterThanOrEqual(result.contrast(with: BarTint.darkBackground), ArtworkPalette.secondaryContrast)
    }

    func testReadableDarkensPaleColoursInLightMode() {
        let paleYellow = RGB(r: 0.98, g: 0.94, b: 0.6)
        let result = BarTint.readable(paleYellow, dark: false)
        XCTAssertGreaterThanOrEqual(result.contrast(with: BarTint.lightBackground), ArtworkPalette.secondaryContrast)
        XCTAssertLessThan(result.luminance, paleYellow.luminance)
    }

    func testReadableLeavesReadableColoursAlone() {
        let orange = RGB(r: 0.95, g: 0.5, b: 0.1)
        XCTAssertEqual(BarTint.readable(orange, dark: true), orange)
    }
}
