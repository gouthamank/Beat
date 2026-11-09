import XCTest
@testable import Beat

final class AlbumSongsLayoutTests: XCTestCase {
    private let metrics = AlbumSongsLayout.Metrics(song: 26, songWithArtist: 40, artist: 36, padding: 14, coverTitle: 24, year: 15)

    private func album(_ id: PersistentID, artist: String = "Artist", year: Int = 2000) -> Album {
        Album(id: id, title: "Album \(id)", artist: artist, year: year, genre: "Rock", isCompilation: false,
              dateAdded: nil, trackIDs: [], duration: 0, discCount: 1)
    }

    private func group(_ album: Album, _ ids: [PersistentID], artist: String? = nil) -> SongGroup {
        SongGroup(album: album, tracks: ids.map { Track.fixture(id: $0, albumID: album.id, artist: artist ?? album.artist) })
    }

    /// Artist A with a long album (1) and a short one (2); artist B with one song by a guest artist.
    private var sections: [ArtistSection] {
        [
            ArtistSection(name: "A", groups: [group(album(1, artist: "A"), [10, 11, 12, 13, 14, 15, 16, 17]),
                                              group(album(2, artist: "A", year: 0), [20])]),
            ArtistSection(name: "B", groups: [group(album(3, artist: "B"), [30], artist: "Guest")]),
        ]
    }

    func testRowOrder() {
        let layout = AlbumSongsLayout(sections: sections, metrics: metrics)
        XCTAssertEqual(layout.rows.prefix(3), [.artist(section: 0), .albumTop(album: 0), .song(album: 0, track: 0, play: 0)])
        XCTAssertEqual(layout.rows.count, 2 + (2 + 8) + (2 + 1) + (2 + 1))
        XCTAssertEqual(layout.albums.map(\.isFirstInSection), [true, false, true])
        XCTAssertEqual(layout.rows[layout.albums[1].top], .albumTop(album: 1))
        XCTAssertEqual(layout.rows[layout.albums[1].bottom], .albumBottom(album: 1))
    }

    func testPlayIndexFollowsPageOrder() {
        let layout = AlbumSongsLayout(sections: sections, metrics: metrics)
        let order = sections.flatMap(\.groups).flatMap(\.tracks).map(\.id)
        for (play, id) in order.enumerated() {
            let row = try! XCTUnwrap(layout.rowOfTrack[id])
            guard case .song(_, _, let index) = layout.rows[row] else { return XCTFail("row \(row) isn't a song") }
            XCTAssertEqual(index, play)
            XCTAssertTrue(layout.isSong(row))
        }
        XCTAssertFalse(layout.isSong(0))
    }

    func testBottomSpacerMakesRoomForTheCover() {
        let layout = AlbumSongsLayout(sections: sections, metrics: metrics)
        let art: CGFloat = 160
        // Album 1: eight songs (208) are taller than the cover block (160 + 24 + 15 = 199), so just padding.
        XCTAssertEqual(layout.height(of: layout.albums[0].bottom, artWidth: art), 14)
        // Album 2: one song (26), no year: the cover block (184) plus padding minus the song.
        XCTAssertEqual(layout.coverHeight(album: 1, artWidth: art), 184)
        XCTAssertEqual(layout.height(of: layout.albums[1].bottom, artWidth: art), 184 + 14 - 26)
        // A wider cover column grows the spacer with it.
        XCTAssertEqual(layout.height(of: layout.albums[1].bottom, artWidth: 200), 224 + 14 - 26)
    }

    func testGuestArtistRowsAreTaller() {
        let layout = AlbumSongsLayout(sections: sections, metrics: metrics)
        XCTAssertEqual(layout.height(of: try XCTUnwrap(layout.rowOfTrack[30]), artWidth: 160), 40)
        XCTAssertEqual(layout.height(of: try XCTUnwrap(layout.rowOfTrack[10]), artWidth: 160), 26)
    }

    func testAlbumRangeOverlappingRows() {
        let layout = AlbumSongsLayout(sections: sections, metrics: metrics)
        let a = layout.albums
        XCTAssertEqual(layout.albumRange(overlapping: 0, 0), 0..<0, "the artist header alone")
        XCTAssertEqual(layout.albumRange(overlapping: a[0].top + 3, a[0].top + 3), 0..<1, "mid-album")
        XCTAssertEqual(layout.albumRange(overlapping: a[0].bottom, a[2].top), 0..<3)
        XCTAssertEqual(layout.albumRange(overlapping: a[2].bottom, a[2].bottom), 2..<3)
    }

    func testEmpty() {
        let layout = AlbumSongsLayout(sections: [], metrics: metrics)
        XCTAssertTrue(layout.rows.isEmpty)
        XCTAssertEqual(layout.albumRange(overlapping: 0, 10), 0..<0)
    }
}
