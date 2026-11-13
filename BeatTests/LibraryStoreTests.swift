import XCTest
@testable import Beat

@MainActor
final class LibraryStoreTests: XCTestCase {
    private var cache: URL!

    override func setUp() async throws {
        cache = try temporaryFolder()
    }

    private func store(_ source: FakeLibrarySource, stamp: @escaping @Sendable () -> Date? = { nil }) -> LibraryStore {
        LibraryStore(loader: source, cacheDirectory: cache, libraryStamp: stamp)
    }

    private let one = [Track.fixture(id: 1)]
    private let two = [Track.fixture(id: 1), Track.fixture(id: 2, title: "Second")]

    func testShowsTheSavedLibraryWhileReadingTheRealOne() async {
        await LibraryCache.save(one, in: cache)
        let source = FakeLibrarySource(tracks: two)
        await source.holdNext()
        let library = store(source)

        let load = Task { await library.load() }
        await eventually("the read never started") { await source.isHolding }
        XCTAssertEqual(library.snapshot.tracks.map(\.id), [1], "the saved library, at once")
        XCTAssertEqual(library.state, .loaded)
        XCTAssertEqual(library.version, 1)

        await source.release()
        await load.value
        XCTAssertEqual(library.snapshot.tracks.map(\.id), [1, 2])
        XCTAssertEqual(library.version, 2)
    }

    func testAReadThatChangedNothingKeepsTheSnapshot() async {
        let library = store(FakeLibrarySource(tracks: two))
        var reads = 0, artChanges = 0
        library.onRead = { _ in reads += 1 }
        library.onArtworkChanged = { _ in artChanges += 1 }

        await library.load()
        await library.load()
        XCTAssertEqual(library.version, 1, "derived results aren't recomputed")
        XCTAssertEqual(reads, 2, "saved thumbnails are still checked after every read")
        XCTAssertEqual(artChanges, 1)
    }

    func testANewReadIsSavedForTheNextLaunch() async {
        await store(FakeLibrarySource(tracks: two)).load()
        await eventually("never saved") { await LibraryCache.load(from: self.cache)?.tracks.count == 2 }
    }

    func testChangedArtIsReported() async {
        var changed: Set<ArtworkSource> = []
        var old = Track.fixture(id: 1, hasArtwork: true)
        old.dateModified = Date(timeIntervalSince1970: 1000)
        var new = old
        new.dateModified = Date(timeIntervalSince1970: 2000)
        let library = store(FakeLibrarySource([.success(.build(tracks: [old])), .success(.build(tracks: [new]))]))
        library.onArtworkChanged = { changed = $0 }

        await library.load()
        await library.load()
        XCTAssertTrue(changed.contains(.album(1)), "the album's cover changed in Music")
    }

    func testLosingAccessLeavesNothingBehind() async {
        await LibraryCache.save(one, in: cache)
        let library = store(FakeLibrarySource([.failure(TestError())]))
        var lost = false
        library.onAccessLost = { lost = true }

        await library.load()
        XCTAssertTrue(library.snapshot.tracks.isEmpty, "the saved library came off screen")
        XCTAssertTrue(lost)
        guard case .failed = library.state else { return XCTFail("shows the failure") }
        let saved = await LibraryCache.load(from: cache)
        XCTAssertNil(saved, "and off disk")
    }

    func testRequestsDuringAReadBecomeOneMoreRead() async {
        let source = FakeLibrarySource(tracks: two)
        await source.holdNext()
        let library = store(source)

        let first = Task { await library.load() }
        await eventually("the read never started") { await source.isHolding }
        await library.load()
        await library.load()
        await source.release()
        await first.value
        let reads = await source.reads
        XCTAssertEqual(reads, 2, "two requests mid-read, one more read")
    }

    func testReadsAgainOnlyWhenTheLibraryWasWritten() async {
        let stamp = Stamp(Date(timeIntervalSince1970: 100))
        let source = FakeLibrarySource(tracks: two)
        let library = store(source) { stamp.date }

        await library.load()
        await library.reloadIfMusicChanged()
        var reads = await source.reads
        XCTAssertEqual(reads, 1, "nothing written since the read")

        stamp.date = Date(timeIntervalSince1970: 200)
        await library.reloadIfMusicChanged()
        reads = await source.reads
        XCTAssertEqual(reads, 2)
    }
}

/// When the library was last written, changed by the test between reads.
private final class Stamp: @unchecked Sendable {
    var date: Date?
    init(_ date: Date?) { self.date = date }
}

final class FirstLoadGateTests: XCTestCase {
    @MainActor
    func testWaitersResumeOnlyOnceTheGateOpens() async {
        let box = GateBox()
        let waiter = Task { @MainActor in
            await withCheckedContinuation { box.gate.wait($0) }
            box.resumed = true
        }
        for _ in 0..<10 { await Task.yield() }
        XCTAssertFalse(box.resumed, "art asked for before the first read waits")
        box.gate.open()
        await waiter.value
        XCTAssertTrue(box.resumed)
    }

    @MainActor
    func testAnOpenGateLetsEveryoneThrough() async {
        let box = GateBox()
        box.gate.open()
        box.gate.open()
        await withCheckedContinuation { box.gate.wait($0) }
        XCTAssertTrue(box.gate.isOpen)
    }
}

@MainActor
private final class GateBox {
    var gate = FirstLoadGate()
    var resumed = false
}
