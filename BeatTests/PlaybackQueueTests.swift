import XCTest
@testable import Beat

/// `PlaybackQueue` driving a `FakePlayer`: what it asks the player to do, and what it records.
@MainActor
final class PlaybackQueueTests: XCTestCase {
    private var player: FakePlayer!
    private var history: PlayHistoryStore!
    private var queue: PlaybackQueue!

    override func setUp() async throws {
        player = FakePlayer()
        history = PlayHistoryStore(fileURL: nil)
        let artwork = ArtworkCache(loader: FakeLibrarySource(), disk: ArtworkDiskCache(directory: try temporaryFolder()))
        queue = PlaybackQueue(history: history, artwork: artwork, player: player, publishesNowPlaying: false)
    }

    /// Songs with library addresses, as on iPad and iPhone: playable without a file on disk.
    private func songs(_ ids: PersistentID..., duration: TimeInterval = 180) -> [Track] {
        ids.map {
            var track = Track.fixture(id: $0, title: "Song \($0)", duration: duration)
            track.location = Self.url($0)
            return track
        }
    }

    private static func url(_ id: PersistentID) -> URL { URL(string: "ipod-library://item/\(id)")! }

    // MARK: Starting

    func testPlayingLoadsTheChosenSongWithTheNextOneReady() {
        queue.play(songs(1, 2, 3), startAt: 1)
        XCTAssertEqual(player.calls, [.load(Self.url(2), upcoming: Self.url(3), autoplay: true)])
        XCTAssertEqual(queue.current?.id, 2)
        XCTAssertTrue(queue.isPlaying)
    }

    func testSongsWhoseFileHasGoneAreSkipped() throws {
        let folder = try temporaryFolder()
        let present = folder.appendingPathComponent("present.mp3")
        try Data().write(to: present)
        var tracks = songs(1, 2, 3)
        tracks[0].location = folder.appendingPathComponent("moved.mp3")
        tracks[1].location = present

        queue.play(tracks)
        XCTAssertEqual(queue.current?.id, 2)
        XCTAssertEqual(player.calls, [.load(present, upcoming: Self.url(3), autoplay: true)])
    }

    func testShuffledPlayKeepsEverySong() {
        queue.play(songs(1, 2, 3, 4), shuffled: true)
        XCTAssertTrue(queue.isShuffled)
        XCTAssertEqual(Set(queue.state.items.map(\.id)), [1, 2, 3, 4])
    }

    func testPlayNextOnAnEmptyQueueStartsPlaying() {
        queue.playNext(songs(1))
        XCTAssertEqual(player.calls, [.load(Self.url(1), upcoming: nil, autoplay: true)])
        player.clear()
        queue.addToQueue(songs(2))
        XCTAssertEqual(player.calls, [.upcoming(Self.url(2))], "a song added after the current one is preloaded")
    }

    // MARK: Transport

    func testPauseAndPlay() {
        queue.play(songs(1))
        player.clear()
        queue.togglePlayPause()
        XCTAssertFalse(queue.isPlaying)
        queue.togglePlayPause()
        XCTAssertTrue(queue.isPlaying)
        XCTAssertEqual(player.calls, [.pause, .play])
    }

    func testNextAndPrevious() {
        queue.play(songs(1, 2, 3))
        player.clear()
        queue.next()
        XCTAssertEqual(player.calls, [.load(Self.url(2), upcoming: Self.url(3), autoplay: true)])

        player.clear()
        player.onTime?(5)
        queue.previous()
        XCTAssertEqual(player.calls, [.seek(0)], "after 3 seconds, Previous restarts the song")
        XCTAssertEqual(queue.current?.id, 2)

        player.clear()
        queue.previous()
        XCTAssertEqual(player.calls, [.load(Self.url(1), upcoming: Self.url(2), autoplay: true)], "before, it goes back one")
    }

    func testNextOnTheLastSongRewindsAndKeepsIt() {
        queue.play(songs(1))
        player.clear()
        queue.next()
        XCTAssertEqual(player.calls, [.load(Self.url(1), upcoming: nil, autoplay: false)], "paused at its start")
        XCTAssertEqual(queue.current?.id, 1, "the bar keeps it")
        XCTAssertFalse(queue.isPlaying)
        XCTAssertEqual(queue.skippedPastEnd, 1, "full Now Playing closes on it")
    }

    func testStop() {
        queue.play(songs(1, 2))
        queue.stop()
        XCTAssertEqual(player.calls.last, .stop)
        XCTAssertNil(queue.current)
        XCTAssertFalse(queue.isPlaying)
    }

    // MARK: The player's own events

    func testASongEndingMovesToThePreloadedOne() {
        queue.play(songs(1, 2, 3))
        player.clear()
        player.onAdvanced?()
        XCTAssertEqual(queue.current?.id, 2)
        XCTAssertEqual(player.calls, [.upcoming(Self.url(3))], "already playing: only the next one is preloaded")
    }

    func testTheQueueRunningOutLeavesTheLastSongPaused() {
        queue.play(songs(1))
        player.clear()
        player.onFinished?()
        XCTAssertEqual(player.calls, [.load(Self.url(1), upcoming: nil, autoplay: false)])
        XCTAssertFalse(queue.isPlaying)
        XCTAssertEqual(queue.current?.id, 1)
    }

    // MARK: History

    func testAPlayCountsOnceHalfwayThrough() {
        queue.play(songs(1, duration: 180))
        player.onTime?(89)
        XCTAssertNil(history.stats[1])
        player.onTime?(90)
        player.onTime?(150)
        XCTAssertEqual(history.stats[1]?.playCount, 1)
    }

    func testALongSongCountsAfterFourMinutes() {
        queue.play(songs(1, duration: 3600))
        player.onTime?(239)
        XCTAssertNil(history.stats[1])
        player.onTime?(240)
        XCTAssertEqual(history.stats[1]?.playCount, 1)
    }

    func testSkipsCountOnlyBetweenTwoAndTwentySeconds() {
        queue.play(songs(1, 2, 3, 4))
        player.onTime?(1)
        queue.next()
        XCTAssertNil(history.stats[1], "too soon to be a skip")

        player.onTime?(5)
        queue.next()
        XCTAssertEqual(history.stats[2]?.skipCount, 1)

        player.onTime?(25)
        queue.next()
        XCTAssertNil(history.stats[3], "listened long enough")
    }
}
