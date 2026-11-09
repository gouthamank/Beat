import XCTest
@testable import Beat

final class SmartFilterEngineTests: XCTestCase {
    private let now = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func daysAgo(_ n: Int) -> Date { now.addingTimeInterval(-Double(n) * 86_400) }

    /// Albums: 10 "Blue" by Ann (tracks 1-3), 20 "Red" by Bob (4-5), 30 "Green" by Cat (6).
    private lazy var library: [Track] = [
        .fixture(id: 1, title: "Alpha", album: "Blue", albumID: 10, artist: "Ann", track: 1, genre: "Jazz", year: 1999, rating: 100, playCount: 5, duration: 60, dateAdded: daysAgo(400), lastPlayed: daysAgo(2)),
        .fixture(id: 2, title: "Beta", album: "Blue", albumID: 10, artist: "Ann", track: 2, genre: "Jazz", year: 1999, rating: 80, playCount: 1, duration: 120, dateAdded: daysAgo(400), lastPlayed: daysAgo(300)),
        .fixture(id: 3, title: "Gamma Café", album: "Blue", albumID: 10, artist: "Ann", track: 3, genre: "Jazz", year: 1999, rating: 0, playCount: 0, duration: 180, dateAdded: daysAgo(400)),
        .fixture(id: 4, title: "Delta", album: "Red", albumID: 20, artist: "Bob", track: 1, genre: "Rock", year: 2010, rating: 60, playCount: 20, duration: 240, dateAdded: daysAgo(10), lastPlayed: daysAgo(40)),
        .fixture(id: 5, title: "Epsilon", album: "Red", albumID: 20, artist: "Bob", track: 2, genre: "Rock", year: 2010, rating: 40, playCount: 2, duration: 300, dateAdded: daysAgo(10)),
        .fixture(id: 6, title: "Zeta", album: "Green", albumID: 30, artist: "Cat", track: 1, genre: "Pop", year: 2020, rating: 20, playCount: 8, duration: 200, dateAdded: daysAgo(100), lastPlayed: daysAgo(1)),
    ]

    private func prepared(history: [PersistentID: PlayHistoryStore.Stats] = [:]) -> PreparedLibrary {
        PreparedLibrary(snapshot: .build(tracks: library), history: history, now: now, calendar: calendar)
    }

    private func run(_ steps: [FilterStep], output: ResultKind = .songs, in lib: PreparedLibrary? = nil) -> FilterResult {
        let filter = SmartFilter(id: UUID(), name: "T", output: output, steps: steps)
        return SmartFilterEngine.evaluate(filter, in: lib ?? prepared())
    }

    private func ids(_ r: FilterResult) -> [PersistentID] { r.tracks.map(\.id) }
    private func rule(_ f: Field, _ op: RuleOperator, _ v: RuleValue) -> RuleNode { .rule(Rule(field: f, op: op, value: v)) }
    private func filter(_ match: Match = .all, _ nodes: RuleNode...) -> FilterStep { .filter(RuleGroup(match: match, nodes: nodes)) }

    // MARK: Text

    func testTextOperators() {
        XCTAssertEqual(ids(run([filter(.all, rule(.title, .is, .text("alpha")))])), [1])
        XCTAssertEqual(ids(run([filter(.all, rule(.title, .contains, .text("CAFE")))])), [3], "case and diacritic insensitive")
        XCTAssertEqual(ids(run([filter(.all, rule(.title, .beginsWith, .text("Ep")))])), [5])
        XCTAssertEqual(ids(run([filter(.all, rule(.title, .endsWith, .text("ta")))])), [2, 4, 6])
        XCTAssertEqual(ids(run([filter(.all, rule(.genre, .isNot, .text("jazz")))])), [4, 5, 6])
        XCTAssertEqual(ids(run([filter(.all, rule(.artist, .doesNotContain, .text("b")))])), [1, 2, 3, 6])
    }

    // MARK: Numbers

    func testNumberOperators() {
        XCTAssertEqual(ids(run([filter(.all, rule(.playCount, .is, .number(0)))])), [3])
        XCTAssertEqual(ids(run([filter(.all, rule(.playCount, .greaterThan, .number(5)))])), [4, 6])
        XCTAssertEqual(ids(run([filter(.all, rule(.year, .lessThan, .number(2010)))])), [1, 2, 3])
        XCTAssertEqual(ids(run([filter(.all, rule(.year, .inRange, .range(2020, 2005)))])), [4, 5, 6], "range bounds in either order")
        XCTAssertEqual(ids(run([filter(.all, rule(.rating, .greaterThan, .number(3)))])), [1, 2], "rating compares in stars")
    }

    // MARK: Dates

    func testRelativeDates() {
        XCTAssertEqual(ids(run([filter(.all, rule(.lastPlayed, .inLast, .relative(1, .weeks)))])), [1, 6])
        XCTAssertEqual(ids(run([filter(.all, rule(.lastPlayed, .notInLast, .relative(1, .months)))])), [2, 3, 4, 5], "never played counts as not in the last N")
        XCTAssertEqual(ids(run([filter(.all, rule(.dateAdded, .inLast, .relative(1, .years)))])), [4, 5, 6])
    }

    func testAbsoluteDates() {
        XCTAssertEqual(ids(run([filter(.all, rule(.dateAdded, .before, .date(daysAgo(50))))])), [1, 2, 3, 6])
        XCTAssertEqual(ids(run([filter(.all, rule(.lastPlayed, .after, .date(daysAgo(5))))])), [1, 6])
    }

    // MARK: Groups

    func testNestedGroups() {
        // (rating >= 4 stars OR plays > 9) AND not played in the last 6 months
        let step = filter(.all,
            .group(RuleGroup(match: .any, nodes: [
                rule(.rating, .greaterThan, .number(3)),
                rule(.playCount, .greaterThan, .number(9)),
            ])),
            rule(.lastPlayed, .notInLast, .relative(6, .months))
        )
        XCTAssertEqual(ids(run([step])), [2])
    }

    func testMatchNoneAndEmptyGroup() {
        XCTAssertEqual(ids(run([filter(.none, rule(.genre, .is, .text("Jazz")), rule(.genre, .is, .text("Pop")))])), [4, 5])
        XCTAssertEqual(ids(run([filter(.all)])).count, 6, "an empty group matches everything")
    }

    func testBoolRules() {
        XCTAssertEqual(ids(run([filter(.all, rule(.compilation, .isTrue, .none))])), [])
        XCTAssertEqual(ids(run([filter(.all, rule(.compilation, .isFalse, .none))])).count, 6)
    }

    // MARK: Sort and limit

    func testSortThenLimitDiffersFromLimitThenSort() {
        let byPlays = FilterStep.sort([SortKey(field: .field(.playCount), ascending: false)])
        let two = FilterStep.limit(Limit(count: 2, unit: .songs))
        XCTAssertEqual(ids(run([byPlays, two])), [4, 6])
        XCTAssertEqual(ids(run([two, byPlays])), [1, 2])
    }

    func testMultiKeySortAndMissingValuesLast() {
        let r = run([.sort([SortKey(field: .field(.year), ascending: true), SortKey(field: .field(.title), ascending: false)])])
        XCTAssertEqual(ids(r), [3, 2, 1, 5, 4, 6])
        let byLastPlayed = run([.sort([SortKey(field: .field(.lastPlayed), ascending: true)])])
        XCTAssertEqual(Array(ids(byLastPlayed).suffix(2)), [3, 5], "never-played sorts last even ascending")
    }

    func testAlbumSortUsesAggregates() {
        // Total plays: Blue 6, Red 22, Green 8.
        let r = run([.sort([SortKey(field: .field(.playCount), ascending: false)])], output: .albums)
        XCTAssertEqual(r.albums.map(\.title), ["Red", "Green", "Blue"])
        XCTAssertEqual(ids(r), [4, 5, 6, 1, 2, 3], "tracks stay grouped by album")
    }

    func testEntityLimits() {
        let r = run([.sort([SortKey(field: .field(.playCount), ascending: false)]), .limit(Limit(count: 2, unit: .artists))])
        XCTAssertEqual(ids(r), [4, 6, 5], "songs from the first two artists encountered (Bob, Cat)")
        let albums = run([.limit(Limit(count: 1, unit: .albums))], output: .albums)
        XCTAssertEqual(albums.albums.map(\.id), [10])
    }

    func testTimeLimit() {
        XCTAssertEqual(ids(run([.limit(Limit(count: 6, unit: .minutes))])), [1, 2, 3], "60+120+180 = 360s fits, adding 240 doesn't")
    }

    func testRandomSortIsStablePerDayAndKeepsAllItems() {
        let filter = SmartFilter(id: UUID(), name: "R", output: .albums, steps: [.sort([SortKey(field: .random, ascending: true)])])
        let a = SmartFilterEngine.evaluate(filter, in: prepared())
        let b = SmartFilterEngine.evaluate(filter, in: prepared())
        XCTAssertEqual(a.albums.map(\.id), b.albums.map(\.id))
        XCTAssertEqual(Set(a.albums.map(\.id)), [10, 20, 30])
    }

    // MARK: Projection and history

    func testArtistAndGenreProjection() {
        let artists = run([.sort([SortKey(field: .field(.playCount), ascending: false)])], output: .artists)
        XCTAssertEqual(artists.artists.map(\.name), ["Bob", "Cat", "Ann"])
        let genres = run([filter(.all, rule(.year, .greaterThan, .number(2000)))], output: .genres)
        XCTAssertEqual(genres.genres.map(\.name), ["Rock", "Pop"])
    }

    func testBeatHistoryIsMergedIntoStats() {
        var stats = PlayHistoryStore.Stats()
        stats.playCount = 50
        stats.lastPlayed = daysAgo(0)
        let lib = prepared(history: [3: stats])
        let r = run([.sort([SortKey(field: .field(.playCount), ascending: false)]), .limit(Limit(count: 1, unit: .songs))], in: lib)
        XCTAssertEqual(ids(r), [3])
        XCTAssertEqual(ids(run([filter(.all, rule(.lastPlayed, .inLast, .relative(1, .days)))], in: lib)), [3, 6], "boundary is inclusive")
    }

    // MARK: Persistence

    func testFiltersRoundTripThroughJSON() throws {
        let data = try JSONEncoder().encode(Presets.all)
        let decoded = try JSONDecoder().decode([SmartFilter].self, from: data)
        XCTAssertEqual(decoded, Presets.all)
    }

    func testPresetsEvaluateWithoutCrashing() {
        let lib = prepared()
        for preset in Presets.all {
            _ = SmartFilterEngine.evaluate(preset, in: lib)
        }
    }
}
