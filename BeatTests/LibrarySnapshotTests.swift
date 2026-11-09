import XCTest
@testable import Beat

final class LibrarySnapshotTests: XCTestCase {
    func testAlbumsGroupAndOrderTracks() {
        let tracks = [
            Track.fixture(id: 1, title: "B", album: "X", albumID: 10, albumArtist: "Ann", track: 2),
            Track.fixture(id: 2, title: "A", album: "X", albumID: 10, albumArtist: "Ann", track: 1),
            Track.fixture(id: 3, title: "C", album: "X", albumID: 10, albumArtist: "Ann", track: 1, disc: 2),
        ]
        let snapshot = LibrarySnapshot.build(tracks: tracks)
        XCTAssertEqual(snapshot.albums.count, 1)
        XCTAssertEqual(snapshot.albums[0].trackIDs, [2, 1, 3])
        XCTAssertEqual(snapshot.albums[0].discCount, 2)
        XCTAssertEqual(snapshot.artists.map(\.name), ["Ann"])
    }

    func testAlbumHasArtworkWhenAnyTrackDoes() throws {
        let snapshot = LibrarySnapshot.build(tracks: [
            .fixture(id: 1, albumID: 10), .fixture(id: 2, albumID: 10, track: 2, hasArtwork: true),
            .fixture(id: 3, album: "Bare", albumID: 20),
        ])
        XCTAssertTrue(snapshot.hasArtwork(try XCTUnwrap(snapshot.albumsByID[10])))
        XCTAssertFalse(snapshot.hasArtwork(try XCTUnwrap(snapshot.albumsByID[20])))
    }

    func testAlbumCoverIsFirstTrackWithArtworkInAlbumOrder() throws {
        // Library order puts track 3 first; the cover still comes from track 2, the first in album order with art.
        let snapshot = LibrarySnapshot.build(tracks: [
            .fixture(id: 3, albumID: 10, track: 3, hasArtwork: true),
            .fixture(id: 1, albumID: 10, track: 1),
            .fixture(id: 2, albumID: 10, track: 2, hasArtwork: true),
        ])
        XCTAssertEqual(snapshot.artworkTrackID(of: try XCTUnwrap(snapshot.albumsByID[10])), 2)
    }

    func testNowPlayingArtIsTheTracksOwnElseTheAlbums() {
        XCTAssertEqual(ArtworkSource(.fixture(id: 5, albumID: 10, hasArtwork: true)), .track(5))
        XCTAssertEqual(ArtworkSource(.fixture(id: 6, albumID: 10)), .album(10))
    }

    func testAlbumSearchMatchesEveryWordAcrossTitleAndArtists() {
        let snapshot = LibrarySnapshot.build(tracks: [
            .fixture(id: 1, album: "Lost Frequencies", albumID: 10, artist: "ASC"),
            .fixture(id: 2, album: "Other", albumID: 20, artist: "Someone"),
        ])
        XCTAssertEqual(snapshot.albums(snapshot.albums, matching: "asc lost").map(\.id), [10])
        XCTAssertEqual(snapshot.albums(snapshot.albums, matching: "  ").count, 2, "blank search keeps everything")
        XCTAssertTrue(snapshot.albums(snapshot.albums, matching: "asc other").isEmpty, "every word must match one album")
    }

    func testCompilationWithoutAlbumArtistIsVariousArtists() {
        let tracks = [
            Track.fixture(id: 1, album: "Hits", albumID: 5, artist: "P", compilation: true),
            Track.fixture(id: 2, album: "Hits", albumID: 5, artist: "Q", compilation: true),
        ]
        let snapshot = LibrarySnapshot.build(tracks: tracks)
        XCTAssertEqual(snapshot.albums[0].artist, LibrarySnapshot.variousArtists)
        XCTAssertTrue(snapshot.artists.isEmpty)
    }

    func testAlbumSearchTextIncludesTrackArtists() {
        let tracks = [
            Track.fixture(id: 1, title: "A", album: "The Raw Truth", albumID: 7, artist: "Lynx + Kemo", albumArtist: "Lynx"),
            Track.fixture(id: 2, title: "B", album: "The Raw Truth", albumID: 7, artist: "Kate Whitmore"),
            Track.fixture(id: 3, title: "C", album: "Sampler", albumID: 8, artist: "Café Del Mar", compilation: true),
        ]
        let snapshot = LibrarySnapshot.build(tracks: tracks)
        let raw = snapshot.albumSearchText[7] ?? ""
        XCTAssertTrue(SearchText.matches(raw, SearchText.words("whitmore raw")), "featured artist plus title")
        XCTAssertTrue(SearchText.matches(raw, SearchText.words("kemo")))
        XCTAssertTrue(SearchText.matches(snapshot.albumSearchText[8] ?? "", SearchText.words("cafe")), "compilation track artist, diacritics folded")
        XCTAssertFalse(SearchText.matches(raw, SearchText.words("sampler")))
    }
}

extension Track {
    static func fixture(
        id: PersistentID,
        title: String = "Song",
        album: String = "Album",
        albumID: PersistentID = 1,
        artist: String = "Artist",
        albumArtist: String = "",
        track: Int = 1,
        disc: Int = 1,
        compilation: Bool = false,
        hasArtwork: Bool = false,
        genre: String = "Rock",
        year: Int = 2000,
        rating: Int = 0,
        playCount: Int = 0,
        duration: TimeInterval = 180,
        dateAdded: Date? = nil,
        lastPlayed: Date? = nil
    ) -> Track {
        Track(
            id: id, title: title, artist: artist, albumArtist: albumArtist, album: album, albumID: albumID,
            composer: "", genre: genre, kind: "MPEG audio file", comments: "", grouping: "",
            year: year, rating: rating, playCount: playCount, skipCount: 0, bpm: 0, bitrate: 256, sampleRate: 44100,
            trackNumber: track, discNumber: disc, duration: duration,
            dateAdded: dateAdded, dateModified: nil, lastPlayed: lastPlayed, lastSkipped: nil,
            isCompilation: compilation, hasArtwork: hasArtwork,
            location: URL(fileURLWithPath: "/tmp/\(id).mp3"), fileSize: 1
        )
    }
}
