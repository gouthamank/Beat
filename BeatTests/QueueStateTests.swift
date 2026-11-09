import XCTest
@testable import Beat

final class QueueStateTests: XCTestCase {
    private let tracks = (1...5).map { Track.fixture(id: PersistentID($0)) }

    private func ids(_ s: QueueState) -> [PersistentID] { s.items.map(\.id) }

    func testAdvanceStopsAtEndWhenRepeatOff() {
        var s = QueueState()
        s.load(tracks, startAt: 3)
        XCTAssertEqual(s.index(after: 3, manual: false), 4)
        XCTAssertNil(s.index(after: 4, manual: false))
    }

    func testRepeatAllWraps() {
        var s = QueueState()
        s.load(tracks, startAt: 4)
        s.repeatMode = .all
        XCTAssertEqual(s.index(after: 4, manual: false), 0)
        XCTAssertEqual(s.index(before: 0), 4)
    }

    func testRepeatOneRepeatsUnlessManual() {
        var s = QueueState()
        s.load(tracks, startAt: 2)
        s.repeatMode = .one
        XCTAssertEqual(s.index(after: 2, manual: false), 2)
        XCTAssertEqual(s.index(after: 2, manual: true), 3)
    }

    func testSkipsUnplayableTracks() {
        var s = QueueState()
        s.load(tracks, startAt: 0)
        let playable: (Track) -> Bool = { $0.id != 2 && $0.id != 3 }
        XCTAssertEqual(s.index(after: 0, manual: false, isPlayable: playable), 3)
        XCTAssertEqual(s.index(before: 3, isPlayable: playable), 0)
    }

    func testNothingPlayableReturnsNil() {
        var s = QueueState()
        s.load(tracks, startAt: 0)
        s.repeatMode = .all
        XCTAssertNil(s.index(after: 0, manual: false, isPlayable: { $0.id == 99 }))
    }

    func testShuffleKeepsCurrentFirstAndRestores() {
        var s = QueueState()
        var rng = SeededRNG(seed: 42)
        s.load(tracks, startAt: 2, shuffled: false, using: &rng)
        s.setShuffle(true, using: &rng)
        XCTAssertEqual(s.index, 0)
        XCTAssertEqual(s.current?.id, 3)
        XCTAssertEqual(Set(ids(s)), Set(tracks.map(\.id)))

        s.move(to: 3)
        let playing = s.current!.id
        s.setShuffle(false, using: &rng)
        XCTAssertEqual(ids(s), [1, 2, 3, 4, 5])
        XCTAssertEqual(s.current?.id, playing)
    }

    func testInsertNextAndAppend() {
        var s = QueueState()
        s.load(Array(tracks.prefix(3)), startAt: 0)
        s.insertNext([Track.fixture(id: 9)])
        s.append([Track.fixture(id: 10)])
        XCTAssertEqual(ids(s), [1, 9, 10, 2, 3], "added songs play before the rest of the list")
        XCTAssertEqual(s.queued.map(\.id), [9, 10])
        XCTAssertEqual(s.continuing.map(\.id), [2, 3])
    }

    func testAddToQueueGoesAfterEarlierAdditionsAndPlayNextBeforeThem() {
        var s = QueueState()
        s.load(tracks, startAt: 0)
        s.append([Track.fixture(id: 10)])
        s.append([Track.fixture(id: 11)])
        s.insertNext([Track.fixture(id: 9)])
        XCTAssertEqual(ids(s), [1, 9, 10, 11, 2, 3, 4, 5])
    }

    func testPlayingAddedSongsUsesThemUp() {
        var s = QueueState()
        s.load(tracks, startAt: 0)
        s.append([Track.fixture(id: 10), Track.fixture(id: 11)])
        s.move(to: 1)
        XCTAssertEqual(s.queued.map(\.id), [11])
        s.append([Track.fixture(id: 12)])
        XCTAssertEqual(ids(s), [1, 10, 11, 12, 2, 3, 4, 5])
        s.move(to: 4)
        XCTAssertEqual(s.queuedCount, 0, "skipping past the added songs ends the run")
    }

    func testGoingBackEndsTheRun() {
        var s = QueueState()
        s.load(tracks, startAt: 2)
        s.append([Track.fixture(id: 10)])
        s.move(to: 1)
        XCTAssertEqual(s.queuedCount, 0)
    }

    func testRemovingAndClearingAddedSongs() {
        var s = QueueState()
        s.load(tracks, startAt: 0)
        s.append([Track.fixture(id: 10), Track.fixture(id: 11)])
        s.remove(at: 1)
        XCTAssertEqual(s.queued.map(\.id), [11])
        s.append([Track.fixture(id: 12)])
        s.clearQueued()
        XCTAssertEqual(ids(s), [1, 2, 3, 4, 5])
        XCTAssertEqual(s.queuedCount, 0)
    }

    func testShuffleKeepsAddedSongsNextAndInOrder() {
        var s = QueueState()
        var rng = SeededRNG(seed: 3)
        s.load(tracks, startAt: 1)
        s.append([Track.fixture(id: 10), Track.fixture(id: 11)])
        s.setShuffle(true, using: &rng)
        XCTAssertEqual(Array(ids(s).prefix(3)), [2, 10, 11])
        XCTAssertEqual(Set(ids(s).dropFirst(3)), [1, 3, 4, 5])
        s.setShuffle(false, using: &rng)
        XCTAssertEqual(ids(s), [1, 2, 10, 11, 3, 4, 5])
        XCTAssertEqual(s.queued.map(\.id), [10, 11])
    }

    func testInsertNextWhileShuffledSurvivesUnshuffle() {
        var s = QueueState()
        var rng = SeededRNG(seed: 7)
        s.load(tracks, startAt: 1, shuffled: true, using: &rng)
        s.insertNext([Track.fixture(id: 9)])
        XCTAssertEqual(s.items[1].id, 9)
        s.setShuffle(false, using: &rng)
        XCTAssertEqual(ids(s), [1, 2, 9, 3, 4, 5])
    }

    func testRemoveBeforeCurrentShiftsIndex() {
        var s = QueueState()
        s.load(tracks, startAt: 3)
        s.remove(at: 1)
        XCTAssertEqual(s.current?.id, 4)
        s.remove(at: s.index!) // current can't be removed
        XCTAssertEqual(s.current?.id, 4)
        XCTAssertEqual(s.items.count, 4)
    }

    // MARK: Up Next editing

    func testMoveUpNextReordersOnlyAfterCurrent() {
        var s = QueueState()
        s.load(tracks, startAt: 1)          // current 2, up next 3 4 5
        s.moveUpNext(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(ids(s), [1, 2, 5, 3, 4])
        XCTAssertEqual(s.current?.id, 2)
        s.moveUpNext(fromOffsets: [0], toOffset: 3)
        XCTAssertEqual(ids(s), [1, 2, 3, 4, 5], "moving to the end uses the offset before the move")
    }

    func testMoveUpNextWhileShuffledKeepsOriginalOrder() {
        var s = QueueState()
        var rng = SeededRNG(seed: 7)
        s.load(tracks, startAt: 0, shuffled: true, using: &rng)
        let current = s.current?.id
        s.moveUpNext(fromOffsets: [0], toOffset: 4)
        XCTAssertEqual(s.current?.id, current)
        s.setShuffle(false, using: &rng)
        XCTAssertEqual(ids(s), [1, 2, 3, 4, 5], "turning shuffle off restores the album order")
        XCTAssertEqual(s.current?.id, current)
    }

    func testClearUpNext() {
        var s = QueueState()
        s.load(tracks, startAt: 2)
        s.clearUpNext()
        XCTAssertEqual(ids(s), [1, 2, 3])
        XCTAssertEqual(s.current?.id, 3)
        XCTAssertTrue(s.upNext.isEmpty)
    }

    func testClearUpNextWhileShuffledDropsThemFromOriginalToo() {
        var s = QueueState()
        var rng = SeededRNG(seed: 3)
        s.load(tracks, startAt: 0, shuffled: true, using: &rng)
        let kept = Set(s.items.prefix(1).map(\.id))
        s.clearUpNext()
        s.setShuffle(false, using: &rng)
        XCTAssertEqual(Set(s.items.map(\.id)), kept)
    }
}
