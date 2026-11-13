import XCTest
@testable import Beat

@MainActor
final class ArtworkCacheTests: XCTestCase {
    private var disk: ArtworkDiskCache!

    override func setUp() async throws {
        disk = ArtworkDiskCache(directory: try temporaryFolder())
    }

    private func cache(art: [ArtworkSource: Data]) -> (ArtworkCache, FakeLibrarySource) {
        let source = FakeLibrarySource(art: art)
        return (ArtworkCache(loader: source, disk: disk), source)
    }

    func testArtIsLoadedOnceThenServedFromMemory() async {
        let (artwork, source) = cache(art: [.album(1): TestImages.png()])
        XCTAssertNil(artwork.cachedImage(album: 1, size: .large))
        let first = await artwork.image(album: 1, size: .large)
        XCTAssertNotNil(first)
        XCTAssertNotNil(artwork.cachedImage(album: 1, size: .large), "there at once for the next view")
        _ = await artwork.image(album: 1, size: .large)
        let requests = await source.artRequests
        XCTAssertEqual(requests, [.album(1)])
    }

    func testRequestsAtTheSameTimeShareOneLoad() async {
        let (artwork, source) = cache(art: [.album(1): TestImages.png()])
        async let a = artwork.image(album: 1, size: .thumbnail)
        async let b = artwork.image(album: 1, size: .thumbnail)
        let images = await [a, b]
        XCTAssertTrue(images.allSatisfy { $0 != nil })
        let requests = await source.artRequests
        XCTAssertEqual(requests.count, 1)
    }

    func testMissingArtIsNil() async {
        let (artwork, _) = cache(art: [:])
        let image = await artwork.image(.track(5), size: .thumbnail)
        XCTAssertNil(image)
    }

    func testChangedArtIsForgottenAndLoadedAgain() async {
        let (artwork, source) = cache(art: [.album(1): TestImages.png(), .album(2): TestImages.png()])
        _ = await artwork.image(album: 1, size: .large)
        _ = await artwork.image(album: 2, size: .large)

        artwork.invalidate([.album(1)])
        XCTAssertEqual(artwork.revision(of: .album(1)), 1, "covers on screen reload")
        XCTAssertEqual(artwork.revision(of: .album(2)), 0)
        XCTAssertNil(artwork.cachedImage(album: 1, size: .large))
        XCTAssertNotNil(artwork.cachedImage(album: 2, size: .large), "other art stays")

        _ = await artwork.image(album: 1, size: .large)
        let requests = await source.artRequests
        XCTAssertEqual(requests.filter { $0 == .album(1) }.count, 2)

        artwork.invalidate([])
        XCTAssertEqual(artwork.revision(of: .album(1)), 1, "nothing changed, nothing bumped")
    }

    func testThumbnailsSavedForTheCurrentArtComeFromDisk() async {
        let label = ArtworkLabel(trackID: 1, modified: 1000)
        await disk.store(TestImages.image(), for: .album(1), label: label)
        let (artwork, source) = cache(art: [:])
        artwork.currentLabel = { _ in label }

        let thumbnail = await artwork.image(album: 1, size: .thumbnail)
        XCTAssertNotNil(thumbnail, "shown before the library has been read")
        let requests = await source.artRequests
        XCTAssertEqual(requests, [], "the library wasn't asked")
    }

    func testAThumbnailSavedForOlderArtIsNotUsed() async {
        await disk.store(TestImages.image(), for: .album(1), label: ArtworkLabel(trackID: 1, modified: 1000))
        let (artwork, source) = cache(art: [.album(1): TestImages.png()])
        artwork.currentLabel = { _ in ArtworkLabel(trackID: 1, modified: 2000) }

        _ = await artwork.image(album: 1, size: .thumbnail)
        let requests = await source.artRequests
        XCTAssertEqual(requests, [.album(1)], "the new art comes from the library")
    }
}
