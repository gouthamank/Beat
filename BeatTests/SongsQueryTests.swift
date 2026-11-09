import XCTest
@testable import Beat

final class SongsQueryTests: XCTestCase {
    private func ids(_ tracks: [Track]) -> [PersistentID] { tracks.map(\.id) }

    private lazy var library: [Track] = [
        .fixture(id: 1, title: "Camera", album: "The Raw Truth", artist: "Lynx + Kemo", genre: "Drum & Bass"),
        .fixture(id: 2, title: "Café Society", album: "Late Nights", artist: "Ann", genre: "Jazz"),
        .fixture(id: 3, title: "Glass Jaw", album: "The Raw Truth", artist: "Lynx + Kemo", genre: "Drum & Bass"),
    ]

    func testEveryWordMustMatchSomewhere() {
        XCTAssertEqual(ids(SongsQuery.apply(library, search: "lynx raw", sort: [], customValues: [:])), [1, 3])
        XCTAssertEqual(ids(SongsQuery.apply(library, search: "lynx glass", sort: [], customValues: [:])), [3])
        XCTAssertEqual(ids(SongsQuery.apply(library, search: "cafe", sort: [], customValues: [:])), [2], "diacritics ignored")
        XCTAssertEqual(ids(SongsQuery.apply(library, search: "  ", sort: [], customValues: [:])), [1, 2, 3])
    }

    func testTextSortsNaturally() {
        let tracks = ["Track 10", "Track 2", "Track 1"].enumerated().map { Track.fixture(id: PersistentID($0.offset + 1), title: $0.element) }
        let sorted = SongsQuery.apply(tracks, search: "", sort: [TrackSort(column: .title)], customValues: [:])
        XCTAssertEqual(sorted.map(\.title), ["Track 1", "Track 2", "Track 10"])
        let reversed = SongsQuery.apply(tracks, search: "", sort: [TrackSort(column: .title, order: .reverse)], customValues: [:])
        XCTAssertEqual(reversed.map(\.title), ["Track 10", "Track 2", "Track 1"])
    }

    func testMissingDatesSortLastBothWays() {
        let now = Date()
        let tracks = [
            Track.fixture(id: 1, lastPlayed: nil),
            Track.fixture(id: 2, lastPlayed: now.addingTimeInterval(-100)),
            Track.fixture(id: 3, lastPlayed: now),
        ]
        XCTAssertEqual(ids(SongsQuery.apply(tracks, search: "", sort: [TrackSort(column: .lastPlayed)], customValues: [:])), [2, 3, 1])
        XCTAssertEqual(ids(SongsQuery.apply(tracks, search: "", sort: [TrackSort(column: .lastPlayed, order: .reverse)], customValues: [:])), [3, 2, 1])
    }

    func testCustomFieldSortUsesPrecomputedValues() {
        let field = CustomField(name: "Cat", source: .album, extraction: .lastParentheses)
        let tracks = [
            Track.fixture(id: 1, album: "Ten (AUX10)"),
            Track.fixture(id: 2, album: "No Number"),
            Track.fixture(id: 3, album: "Two (AUX2)"),
        ]
        let values = SongsQuery.customValues([field], for: tracks)
        XCTAssertEqual(values[field.id]?[3], "AUX2")
        XCTAssertNil(values[field.id]?[2])
        let sort = [TrackSort(column: .custom(field.id))]
        XCTAssertEqual(ids(SongsQuery.apply(tracks, search: "", sort: sort, customValues: values)), [3, 1, 2])
        let reversed = [TrackSort(column: .custom(field.id), order: .reverse)]
        XCTAssertEqual(ids(SongsQuery.apply(tracks, search: "", sort: reversed, customValues: values)), [1, 3, 2])
    }

    func testTiesKeepLibraryOrder() {
        XCTAssertEqual(ids(SongsQuery.apply(library, search: "", sort: [TrackSort(column: .genre)], customValues: [:])), [1, 3, 2])
    }

    func testGroupByAlbumUsesAlbumOrderAndTrackOrder() {
        let tracks = [
            Track.fixture(id: 1, title: "B2", album: "Second", albumID: 20, artist: "Bob", track: 2),
            Track.fixture(id: 2, title: "A1", album: "First", albumID: 10, artist: "Ann", track: 1),
            Track.fixture(id: 3, title: "B1", album: "Second", albumID: 20, artist: "Bob", track: 1),
            Track.fixture(id: 4, title: "Orphan", album: "Gone", albumID: 99),
        ]
        let albums = LibrarySnapshot.build(tracks: Array(tracks.prefix(3))).albums
        let groups = SongsQuery.groupByAlbum(tracks, albums: albums)
        XCTAssertEqual(groups.map(\.album.title), ["First", "Second"], "library album order; unknown albums left out")
        XCTAssertEqual(groups[1].tracks.map(\.title), ["B1", "B2"], "disc/track order within an album")
    }

    func testSectionsSplitConsecutiveAlbumArtists() {
        let tracks = [
            Track.fixture(id: 1, album: "A1", albumID: 1, artist: "Acronym", albumArtist: "Acronym"),
            Track.fixture(id: 2, album: "A2", albumID: 2, artist: "Acronym", albumArtist: "ACRONYM"),
            Track.fixture(id: 3, album: "B1", albumID: 3, artist: "Actress", albumArtist: "Actress"),
        ]
        let groups = SongsQuery.groupByAlbum(tracks, albums: LibrarySnapshot.build(tracks: tracks).albums)
        let sections = SongsQuery.sectionsByArtist(groups)
        XCTAssertEqual(sections.map(\.id), ["acronym", "actress"], "case-insensitive grouping")
        XCTAssertEqual(sections[0].groups.count, 2)
        XCTAssertEqual(sections[0].songCount, 2)
        XCTAssertTrue(SongsQuery.sectionsByArtist([]).isEmpty)
    }
}
