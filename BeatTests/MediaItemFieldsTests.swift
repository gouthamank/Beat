import XCTest
@testable import Beat

/// The mapping every non-Mac library source uses (MediaPlayer on iPad and iPhone, files in the Simulator).
final class MediaItemFieldsTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/music/Artist/Album/01 Song.m4a")

    func testFieldsBecomeATrack() throws {
        let fields = MediaItemFields(
            id: 7, title: "Song", artist: "Featured", albumArtist: "Artist", album: "Album", albumID: 70,
            composer: "Writer", genre: "Electronic", grouping: "EXIT", comments: "Note", year: 2019, stars: 4,
            playCount: 3, skipCount: 1, bpm: 174, trackNumber: 2, discNumber: 1, duration: 300,
            dateAdded: Date(timeIntervalSince1970: 100), lastPlayed: Date(timeIntervalSince1970: 200),
            isCompilation: false, hasArtwork: true, location: file
        )
        let track = try XCTUnwrap(fields.track)
        XCTAssertEqual(track.id, 7)
        XCTAssertEqual(track.albumID, 70)
        XCTAssertEqual(track.title, "Song")
        XCTAssertEqual(track.artist, "Featured")
        XCTAssertEqual(track.albumArtist, "Artist")
        XCTAssertEqual(track.grouping, "EXIT")
        XCTAssertEqual(track.year, 2019)
        XCTAssertEqual(track.rating, 80, "stars become Music's 0–100 scale")
        XCTAssertEqual(track.bpm, 174)
        XCTAssertEqual(track.trackNumber, 2)
        XCTAssertEqual(track.duration, 300)
        XCTAssertTrue(track.hasArtwork)
        XCTAssertEqual(track.location, file)
    }

    func testNoFileMeansNoTrack() {
        // DRM and cloud-only songs have no playable file: skipped, as songs without a location are on the Mac.
        XCTAssertNil(MediaItemFields(id: 1, albumID: 1).track)
    }

    func testMissingValuesGetSensibleDefaults() throws {
        let track = try XCTUnwrap(MediaItemFields(id: 1, albumID: 1, stars: 9, discNumber: 0, location: file).track)
        XCTAssertEqual(track.title, "01 Song", "the file name when there's no title tag")
        XCTAssertEqual(track.artist, "")
        XCTAssertEqual(track.album, "")
        XCTAssertEqual(track.discNumber, 1, "disc 0 means a single disc")
        XCTAssertEqual(track.rating, 100, "stars clamp to five")
        XCTAssertEqual(track.bitrate, 0, "MediaPlayer reports no bitrate, so the format line hides it")
        XCTAssertEqual(track.formatSummary, "AAC", "without rates the format line is just the format")
    }

    func testEmptyTitleFallsBackToTheFileName() throws {
        XCTAssertEqual(try XCTUnwrap(MediaItemFields(id: 1, title: "", albumID: 1, location: file).track).title, "01 Song")
    }
}
