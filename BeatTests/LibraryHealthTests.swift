import XCTest
@testable import Beat

final class LibraryHealthTests: XCTestCase {
    private func targets(_ items: [LibraryHealthReport.Item]) -> [LibraryHealthReport.Item.Target] { items.map(\.target) }

    func testAlbumsWithoutArtwork() {
        let snapshot = LibrarySnapshot.build(tracks: [
            .fixture(id: 1, album: "Covered", albumID: 1, hasArtwork: true),
            .fixture(id: 2, album: "Covered", albumID: 1, track: 2),
            .fixture(id: 3, album: "Bare", albumID: 2),
        ])
        XCTAssertEqual(targets(LibraryHealth.albumsWithoutArtwork(snapshot)), [.album(2)], "one covered song is enough")
    }

    func testAlbumsWithoutYearSayHowManySongs() {
        let snapshot = LibrarySnapshot.build(tracks: [
            .fixture(id: 1, album: "A", albumID: 1, year: 0),
            .fixture(id: 2, album: "A", albumID: 1, track: 2, year: 0),
            .fixture(id: 3, album: "B", albumID: 2, year: 0),
            .fixture(id: 4, album: "B", albumID: 2, track: 2, year: 2001),
            .fixture(id: 5, album: "C", albumID: 3, year: 1999),
        ])
        let items = LibraryHealth.albumsWithoutYear(snapshot)
        XCTAssertEqual(Set(targets(items)), [.album(1), .album(2)])
        XCTAssertEqual(items.first { $0.target == .album(1) }?.problem, "", "the whole album: the title says it")
        XCTAssertEqual(items.first { $0.target == .album(2) }?.problem, "1 of 2 songs")
    }

    func testDuplicatesNeedTheSameNameArtistAndLength() {
        let snapshot = LibrarySnapshot.build(tracks: [
            .fixture(id: 1, title: "Encke Gap", albumID: 1, artist: "Instra:mental", duration: 300),
            .fixture(id: 2, title: "encke gap", albumID: 2, artist: "Instra:Mental", duration: 301.5),
            .fixture(id: 3, title: "Encke Gap", albumID: 3, artist: "Instra:mental", duration: 240),
            .fixture(id: 4, title: "Encke Gap", albumID: 4, artist: "Someone Else", duration: 300),
        ])
        let items = LibraryHealth.duplicates(snapshot)
        XCTAssertEqual(targets(items), [.song(1, album: 1), .song(2, album: 2)],
                       "case doesn't matter; the 4-minute edit and another artist's song aren't copies")
        XCTAssertEqual(items.map(\.problem), ["2 copies", "2 copies"])
    }

    func testSplitAlbums() {
        let snapshot = LibrarySnapshot.build(tracks: [
            .fixture(id: 1, album: "Séance EP", albumID: 1, albumArtist: "Blocks"),
            .fixture(id: 2, album: "Seance EP", albumID: 2, albumArtist: "Blocks"),
            .fixture(id: 3, album: "Séance EP", albumID: 3, albumArtist: "Someone"),
        ])
        let items = LibraryHealth.splitAlbums(snapshot)
        XCTAssertEqual(Set(targets(items)), [.album(1), .album(2)], "accents folded; another artist's album isn't part of it")
        XCTAssertEqual(items.first?.problem, "1 song, one of 2")
    }

    func testMissingFilesUseTheGivenCheckAndSkipNonFiles() {
        var synced = Track.fixture(id: 3, albumID: 1)
        synced.location = URL(string: "ipod-library://item/item.mp3?id=3")!
        let snapshot = LibrarySnapshot.build(tracks: [.fixture(id: 1, albumID: 1), .fixture(id: 2, albumID: 1), synced])
        let items = LibraryHealth.missingFiles(snapshot) { $0.lastPathComponent != "2.mp3" }
        XCTAssertEqual(targets(items), [.song(2, album: 1)])
    }

    func testMixedTags() {
        func track(_ id: PersistentID, _ number: Int, genre: String = "Rock", year: Int = 2000, albumArtist: String = "A",
                   disc: Int = 1) -> Track {
            .fixture(id: id, albumArtist: albumArtist, track: number, disc: disc, genre: genre, year: year)
        }
        XCTAssertEqual(LibraryHealth.mixedTagProblems([track(1, 1), track(2, 2)], compilation: false), [])
        XCTAssertEqual(LibraryHealth.mixedTagProblems([track(1, 1, genre: "Rock"), track(2, 2, genre: "rock")], compilation: false), [],
                       "case doesn't make a genre different")
        XCTAssertEqual(LibraryHealth.mixedTagProblems([track(1, 1, genre: "Rock", year: 1999), track(2, 2, genre: "Jazz")],
                                                      compilation: false),
                       ["Mixed genres", "Mixed years"])
        XCTAssertEqual(LibraryHealth.mixedTagProblems([track(1, 1, genre: "Rock", year: 1999), track(2, 2, genre: "Jazz")],
                                                      compilation: true), [],
                       "compilations may mix genres and years")
        XCTAssertEqual(LibraryHealth.mixedTagProblems([track(1, 1, albumArtist: "A"), track(2, 2, albumArtist: "B")], compilation: true),
                       ["Mixed album artists"])
        XCTAssertEqual(LibraryHealth.mixedTagProblems([track(1, 1), track(2, 2), track(3, 2), track(4, 5)], compilation: false),
                       ["Track 2 repeated", "Tracks 3 and 4 missing"])
        XCTAssertEqual(LibraryHealth.mixedTagProblems([track(1, 1), track(2, 2, disc: 2)], compilation: false),
                       ["Disc 2: Track 1 missing"], "numbered per disc")
    }

    func testMissingTags() {
        let snapshot = LibrarySnapshot.build(tracks: [
            .fixture(id: 1, albumID: 1, albumArtist: "A", genre: "Rock"),
            .fixture(id: 2, albumID: 1, albumArtist: "A", track: 2, genre: ""),
            .fixture(id: 3, albumID: 1, albumArtist: "", track: 3, genre: "Rock"),
            .fixture(id: 4, albumID: 1, albumArtist: "", track: 4, genre: ""),
        ])
        XCTAssertEqual(LibraryHealth.missingTags(snapshot).map(\.problem),
                       ["No genre", "No album artist", "No genre or album artist"])
    }

    func testNumberedLists() {
        XCTAssertEqual(LibraryHealth.numbered("missing", [3]), "Track 3 missing")
        XCTAssertEqual(LibraryHealth.numbered("missing", [3, 5, 9]), "Tracks 3, 5 and 9 missing")
        XCTAssertEqual(LibraryHealth.numbered("missing", [3, 5, 9, 10, 11]), "Tracks 3, 5, 9 and 2 more missing")
    }

    func testReportHasEveryCheckInOrder() {
        let report = LibraryHealth.check(LibrarySnapshot.build(tracks: [.fixture(id: 1, albumArtist: "A", hasArtwork: true)])) { _ in true }
        XCTAssertEqual(report.sections.map(\.check), LibraryHealthReport.Check.allCases)
        XCTAssertEqual(report.problemCount, 0)
    }
}
