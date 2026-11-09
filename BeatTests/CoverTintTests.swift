import XCTest
@testable import Beat

@MainActor
final class CoverTintTests: XCTestCase {
    private let red = ArtworkPalette(background: .init(r: 1, g: 0, b: 0), primary: .init(r: 1, g: 1, b: 1), secondary: .init(r: 0.8, g: 0.8, b: 0.8))
    private let blue = ArtworkPalette(background: .init(r: 0, g: 0, b: 1), primary: .init(r: 1, g: 1, b: 1), secondary: .init(r: 0.8, g: 0.8, b: 0.8))

    /// Album 1 is red, album 2 is blue; artist "a" features album 1 (or `featured`).
    private func makeTint(cached: [PersistentID: ArtworkPalette], enabled: Bool = true) -> CoverTint {
        let tint = CoverTint()
        tint.settle = .zero
        tint.isEnabled = { enabled }
        tint.cachedPalette = { cached[$0] }
        tint.albumForRoute = { route in
            switch route {
            case .album(let id): id
            case .artist(let id): id == "a" ? 1 : nil
            default: nil
            }
        }
        return tint
    }

    func testRoutesPickTheirAlbum() async {
        let tint = makeTint(cached: [1: red, 2: blue])
        tint.show(.album(2))
        await tint.settled()
        XCTAssertEqual(tint.current?.albumID, 2)
        XCTAssertEqual(tint.current?.route, .album(2))

        tint.show(.artist("a"))
        await tint.settled()
        XCTAssertEqual(tint.current?.albumID, 1, "an artist takes its featured album's colours")

        tint.show(.genre("rock"))
        XCTAssertNil(tint.current, "pages without cover colours clear them at once")
        tint.show(nil)
        XCTAssertNil(tint.current)
    }

    func testPlainMeansNoColours() async {
        let tint = makeTint(cached: [1: red], enabled: false)
        tint.show(.album(1))
        await tint.settled()
        XCTAssertNil(tint.current)
    }

    func testLateAnswerForAPageYouLeftIsIgnored() async {
        let tint = makeTint(cached: [2: blue])
        var release: CheckedContinuation<Void, Never>?
        tint.loadPalette = { _ in
            await withCheckedContinuation { release = $0 }
            return self.red
        }
        tint.show(.album(1))        // slow: album 1 isn't cached
        await Task.yield()
        tint.show(.album(2))        // moves on before album 1 answers
        await tint.settled()
        XCTAssertEqual(tint.current?.route, .album(2))

        release?.resume()           // album 1's answer finally arrives
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(tint.current?.route, .album(2), "the late answer mustn't repaint the sidebar")
    }

    func testAnotherPagesColoursClearImmediately() async {
        let tint = makeTint(cached: [1: red])
        tint.show(.album(1))
        await tint.settled()
        tint.settle = .seconds(60)  // the next page's colours are still settling…
        tint.show(.album(2))
        XCTAssertNil(tint.current, "…so the old page's colours are gone rather than shown on the new one")
    }

    func testRefreshKeepsSamePageColoursWhileResolving() async {
        let tint = makeTint(cached: [1: red])
        tint.show(.album(1))
        await tint.settled()
        tint.settle = .seconds(60)
        tint.refresh()
        XCTAssertEqual(tint.current?.albumID, 1, "same page: no flash while re-checking")
    }

    func testRefreshPicksUpANewFeaturedAlbum() async {
        let tint = makeTint(cached: [1: red, 2: blue])
        var featured: PersistentID = 1
        tint.albumForRoute = { _ in featured }
        tint.show(.artist("a"))
        await tint.settled()
        XCTAssertEqual(tint.current?.albumID, 1)
        featured = 2
        tint.refresh()
        await tint.settled()
        XCTAssertEqual(tint.current?.albumID, 2)
        XCTAssertEqual(tint.current?.palette, blue)
    }
}
