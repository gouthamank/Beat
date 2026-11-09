import XCTest
@testable import Beat

final class LyricsTests: XCTestCase {
    private func times(_ lines: [LyricLine]?) -> [TimeInterval] { lines?.map(\.time) ?? [] }

    // MARK: Parsing

    func testTimestampFormats() {
        XCTAssertEqual(LRC.timestamp("01:02"), 62)
        XCTAssertEqual(LRC.timestamp("01:02.5")!, 62.5, accuracy: 0.001)
        XCTAssertEqual(LRC.timestamp("01:02.50")!, 62.5, accuracy: 0.001)
        XCTAssertEqual(LRC.timestamp("01:02.500")!, 62.5, accuracy: 0.001)
        XCTAssertEqual(LRC.timestamp("01:02:50")!, 62.5, accuracy: 0.001)
        XCTAssertNil(LRC.timestamp("ar:Lynx"))
        XCTAssertNil(LRC.timestamp("length: 03:45"))
        XCTAssertNil(LRC.timestamp(""))
    }

    func testHourTimestamps() {
        XCTAssertEqual(LRC.timestamp("1:02:28", hours: true), 3748)
        XCTAssertEqual(LRC.timestamp("1:02:28.5")!, 3748.5, accuracy: 0.001)
        XCTAssertTrue(LRC.colonTagsMeanHours(["0:00:00", "0:03:28", "1:35:57", "ar:Lynx", "00:12.00"]))
        XCTAssertFalse(LRC.colonTagsMeanHours(["00:12:34", "00:15:80"]))
        XCTAssertFalse(LRC.colonTagsMeanHours(["00:12.00", "00:15.00"]))
    }

    func testDJMixTracklistReadsAsHours() {
        let mix = """
            [0:00:00] Marginal - Springhead [CX Digital]
            [0:03:28] Mr Sizef & Unquote - Hours Have No Reverse Motion [Hospital]
            [1:35:57] Rockwell Feat. Stapleton - Patrol The Block
        """
        let lines = LRC.parse(mix)
        XCTAssertEqual(times(lines), [0, 208, 5757])
        XCTAssertEqual(lines?.first?.text, "Marginal - Springhead [CX Digital]")
    }

    func testNumberedTracklistDropsNumbers() {
        let mix = """
        1. [00:00] Diazepam - Distances [Nerve Breaks - Free Release]
        3. [06:51] ?
        18. [60:22] Abstract Elements - Apocalypse [Auxiliary]
        """
        let lines = LRC.parse(mix)
        XCTAssertEqual(times(lines), [0, 411, 3622])
        XCTAssertEqual(lines?.map(\.text), ["Diazepam - Distances [Nerve Breaks - Free Release]", "?",
                                            "Abstract Elements - Apocalypse [Auxiliary]"])
    }

    func testListNumberKeptWithoutTimestamp() {
        XCTAssertEqual(LRC.droppingListNumber("1. First verse"), "1. First verse")
        XCTAssertEqual(LRC.droppingListNumber("12) [01:00] A"), "[01:00] A")
        XCTAssertEqual(LRC.droppingListNumber("[01:00] A"), "[01:00] A")
    }

    func testColonCentisecondsStayMinutes() {
        let lines = times(LRC.parse("[00:12:34]A\n[00:15:80]B"))
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[0], 12.34, accuracy: 0.001)
        XCTAssertEqual(lines[1], 15.8, accuracy: 0.001)
    }

    func testParsesLinesAndSkipsMetadata() {
        let lrc = """
        [ar:Lynx]
        [ti:Camera]
        [00:12.00]First line
        [00:15.50] Second line
        """
        let lines = LRC.parse(lrc)
        XCTAssertEqual(lines?.map(\.text), ["First line", "Second line"])
        XCTAssertEqual(times(lines), [12, 15.5])
    }

    func testSeveralTimestampsOnOneLineAndSorting() {
        let lrc = """
        [00:30.00][00:10.00]Chorus
        [00:20.00]Verse
        """
        let lines = LRC.parse(lrc)
        XCTAssertEqual(lines?.map(\.text), ["Chorus", "Verse", "Chorus"])
        XCTAssertEqual(times(lines), [10, 20, 30])
    }

    func testOffsetShiftsLinesEarlier() {
        let lrc = """
        [offset:+500]
        [00:10.00]A
        [00:20.00]B
        """
        XCTAssertEqual(times(LRC.parse(lrc)), [9.5, 19.5])
    }

    func testBlankTimedLinesAreKeptAsBreaks() {
        let lines = LRC.parse("[00:01.00]A\n[00:05.00]\n[00:09.00]B")
        XCTAssertEqual(lines?.map(\.text), ["A", "", "B"])
    }

    func testPlainTextIsNotSynced() {
        XCTAssertNil(LRC.parse("Just some words\nand more words"))
        XCTAssertNil(LRC.parse("[00:01.00] only one timed line\nplain"))
    }

    // MARK: Current line

    func testCurrentIndex() {
        let lines = [LyricLine(time: 5, text: "a"), LyricLine(time: 10, text: "b"), LyricLine(time: 20, text: "c")]
        XCTAssertNil(LRC.currentIndex(in: lines, at: 2))
        XCTAssertEqual(LRC.currentIndex(in: lines, at: 5), 0)
        XCTAssertEqual(LRC.currentIndex(in: lines, at: 12), 1)
        XCTAssertEqual(LRC.currentIndex(in: lines, at: 20), 2)
        XCTAssertEqual(LRC.currentIndex(in: lines, at: 999), 2)
        XCTAssertNil(LRC.currentIndex(in: [], at: 3))
    }

    // MARK: Source order

    private let synced = "[00:01.00]one\n[00:02.00]two"

    func testSidecarBeatsEverything() {
        let result = LyricsResolver.resolve(sidecar: synced, embedded: "plain words",
                                            online: .init(synced: "[00:05.00]x\n[00:06.00]y", plain: nil))
        XCTAssertEqual(result, .synced(LRC.parse(synced)!))
    }

    func testEmbeddedLRCCountsAsSynced() {
        XCTAssertEqual(LyricsResolver.resolve(sidecar: nil, embedded: synced, online: nil), .synced(LRC.parse(synced)!))
    }

    func testOnlineSyncedBeatsEmbeddedPlain() {
        let online = LyricsResolver.Online(synced: synced, plain: "online plain")
        XCTAssertEqual(LyricsResolver.resolve(sidecar: nil, embedded: "my words", online: online), .synced(LRC.parse(synced)!))
    }

    func testEmbeddedPlainBeatsOnlinePlain() {
        let online = LyricsResolver.Online(synced: nil, plain: "online plain")
        XCTAssertEqual(LyricsResolver.resolve(sidecar: nil, embedded: "my words", online: online), .plain("my words"))
        XCTAssertEqual(LyricsResolver.resolve(sidecar: nil, embedded: "  ", online: online), .plain("online plain"))
    }

    func testInstrumentalAndMissing() {
        XCTAssertEqual(LyricsResolver.resolve(sidecar: nil, embedded: nil, online: .init(instrumental: true)), .instrumental)
        XCTAssertEqual(LyricsResolver.resolve(sidecar: nil, embedded: nil, online: nil), .missing)
    }

    func testOnlineOnlyWantedWithoutLocalSyncedLyrics() {
        XCTAssertTrue(LyricsResolver.wantsOnline(sidecar: nil, embedded: "plain words"))
        XCTAssertFalse(LyricsResolver.wantsOnline(sidecar: nil, embedded: synced))
        XCTAssertFalse(LyricsResolver.wantsOnline(sidecar: synced, embedded: nil))
    }

    // MARK: Cache

    func testCacheFreshness() throws {
        let now = Date()
        let found = CachedLyrics(result: .init(synced: nil, plain: "words"), fetchedAt: now.addingTimeInterval(-400 * 86_400))
        XCTAssertTrue(found.isFresh(now: now), "found lyrics never expire")
        XCTAssertTrue(CachedLyrics(result: nil, fetchedAt: now.addingTimeInterval(-10 * 86_400)).isFresh(now: now))
        XCTAssertFalse(CachedLyrics(result: nil, fetchedAt: now.addingTimeInterval(-31 * 86_400)).isFresh(now: now),
                       "a miss is retried after 30 days")

        let data = try JSONEncoder().encode(found)
        XCTAssertEqual(try JSONDecoder().decode(CachedLyrics.self, from: data), found)
    }

    func testRequestsSendOnlyMatchingFields() throws {
        let track = Track.fixture(id: 1, title: "Camera", album: "The Raw Truth", artist: "Lynx + Kemo", duration: 285.4)
        func items(_ request: URLRequest?) throws -> [URLQueryItem] {
            let url = try XCTUnwrap(request?.url)
            XCTAssertEqual(url.host, "lrclib.net")
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        }
        let exact = try items(LyricsProvider.getRequest(for: track, includeAlbum: true))
        XCTAssertEqual(Set(exact.map(\.name)), ["artist_name", "track_name", "album_name", "duration"])
        XCTAssertEqual(exact.first { $0.name == "duration" }?.value, "285")
        XCTAssertEqual(Set(try items(LyricsProvider.getRequest(for: track, includeAlbum: false)).map(\.name)),
                       ["artist_name", "track_name", "duration"])
        XCTAssertEqual(Set(try items(LyricsProvider.searchRequest(for: track)).map(\.name)), ["artist_name", "track_name"])
    }

    // MARK: Search results

    private func record(_ duration: Double?, synced: String? = nil, plain: String? = nil, instrumental: Bool = false) -> LyricsResolver.Record {
        LyricsResolver.Record(duration: duration, syncedLyrics: synced, plainLyrics: plain, instrumental: instrumental)
    }

    func testBestMatchPrefersSyncedThenPlainThenInstrumental() {
        let records = [record(57, instrumental: true), record(57, plain: "words"), record(56.5, synced: synced)]
        XCTAssertEqual(LyricsResolver.bestMatch(records, duration: 57)?.synced, synced)
        XCTAssertEqual(LyricsResolver.bestMatch(Array(records.prefix(2)), duration: 57)?.plain, "words")
        XCTAssertEqual(LyricsResolver.bestMatch([records[0]], duration: 57)?.instrumental, true)
    }

    func testBestMatchRejectsWrongLength() {
        XCTAssertNil(LyricsResolver.bestMatch([record(62, synced: synced), record(nil, synced: synced)], duration: 57),
                     "a live or extended version, or one with no length, isn't the same recording")
        XCTAssertNotNil(LyricsResolver.bestMatch([record(58.9, synced: synced)], duration: 57), "within 2 seconds counts")
    }

    func testBestMatchBreaksTiesOnClosestLength() {
        let records = [record(58.5, plain: "far"), record(57.2, plain: "near")]
        XCTAssertEqual(LyricsResolver.bestMatch(records, duration: 57)?.plain, "near")
    }

    func testBestMatchSkipsEmptyRecordsAndTimestamplessSynced() {
        XCTAssertNil(LyricsResolver.bestMatch([record(57), record(57, plain: "  ")], duration: 57))
        XCTAssertEqual(LyricsResolver.bestMatch([record(57, synced: "no timestamps here")], duration: 57), nil)
    }
}
