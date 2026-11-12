import CoreGraphics
import XCTest
@testable import Beat

final class LibraryCacheTests: XCTestCase {
    private func track(_ id: PersistentID, album: PersistentID = 10, art: Bool = true, modified: TimeInterval = 1000,
                       trackNumber: Int = 1) -> Track {
        var t = Track.fixture(id: id, albumID: album, track: trackNumber, hasArtwork: art)
        t.dateModified = Date(timeIntervalSince1970: modified)
        return t
    }

    // MARK: Saved library

    func testTrackSurvivesCodableRoundTrip() throws {
        var original = track(1)
        original.lastPlayed = Date(timeIntervalSince1970: 12345)
        let decoded = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testSavedLibraryRoundTrips() throws {
        let tracks = [track(1), track(2, trackNumber: 2)]
        XCTAssertEqual(LibraryCache.decode(try LibraryCache.encode(tracks)), tracks)
    }

    func testSavedLibraryFromAnotherSchemaOrCorruptIsIgnored() {
        let other = Data(#"{"schema": \#(LibraryCache.schema + 1), "tracks": []}"#.utf8)
        XCTAssertNil(LibraryCache.decode(other))
        XCTAssertNil(LibraryCache.decode(Data("not json".utf8)))
    }

    // MARK: Unchanged reloads

    func testSameLibraryOnlyWhenTracksAreIdentical() {
        let tracks = [track(1), track(2, trackNumber: 2)]
        let snapshot = LibrarySnapshot.build(tracks: tracks)
        XCTAssertTrue(snapshot.isSameLibrary(tracks: tracks))

        var edited = tracks
        edited[1].playCount += 1
        XCTAssertFalse(snapshot.isSameLibrary(tracks: edited), "a changed field")
        XCTAssertFalse(snapshot.isSameLibrary(tracks: Array(tracks.reversed())), "reordered")
        XCTAssertFalse(snapshot.isSameLibrary(tracks: tracks + [track(3, trackNumber: 3)]), "a song added")
        XCTAssertFalse(LibrarySnapshot.empty.isSameLibrary(tracks: []), "nothing loaded yet is never the same")
    }

    // MARK: Art labels and changes

    func testAlbumLabelIsItsCoverSongAndWhenItChanged() {
        let snapshot = LibrarySnapshot.build(tracks: [track(1, art: false), track(2, modified: 500, trackNumber: 2)])
        XCTAssertEqual(snapshot.artworkLabel(for: .album(10)), ArtworkLabel(trackID: 2, modified: 500))
        XCTAssertEqual(snapshot.artworkLabel(for: .track(2)), ArtworkLabel(trackID: 2, modified: 500))
        XCTAssertNil(snapshot.artworkLabel(for: .track(1)), "a song without its own art")
        XCTAssertNil(snapshot.artworkLabel(for: .album(99)), "an unknown album")
    }

    func testChangedArtworkFindsEditedSwappedAndRemovedCovers() {
        let old = LibrarySnapshot.build(tracks: [
            track(1, album: 10), track(2, album: 20), track(3, album: 30), track(4, album: 40),
        ])
        let new = LibrarySnapshot.build(tracks: [
            track(1, album: 10),                         // unchanged
            track(2, album: 20, modified: 2000),          // artwork edited in Music: modified date bumped
            track(3, album: 30, art: false), track(5, album: 30, trackNumber: 2), // cover now from another song
            // album 40 removed
            track(6, album: 60),                         // new album: nothing cached to throw away
        ])
        let changed = LibrarySnapshot.changedArtwork(old: old, new: new)
        XCTAssertEqual(changed, [.album(20), .track(2), .album(30), .track(3), .album(40), .track(4)])
    }

    func testNothingChangedMeansNoChangedArtwork() {
        let tracks = [track(1), track(2, album: 20)]
        XCTAssertTrue(LibrarySnapshot.changedArtwork(old: .build(tracks: tracks), new: .build(tracks: tracks)).isEmpty)
    }

    // MARK: Saved thumbnails

    func testThumbnailNamesRoundTripToTheirSource() {
        let label = ArtworkLabel(trackID: 7, modified: 99)
        for source in [ArtworkSource.album(123), .track(456)] {
            let name = ArtworkDiskCache.name(for: source, label: label)
            XCTAssertTrue(name.hasPrefix(ArtworkDiskCache.prefix(for: source)))
            XCTAssertEqual(ArtworkDiskCache.source(of: name), source)
        }
        XCTAssertNil(ArtworkDiskCache.source(of: "x1_2_3.heic"))
    }

    func testSavedThumbnailIsReadOnlyForTheCurrentLabelAndPrunedWhenStale() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let disk = ArtworkDiskCache(directory: directory)
        let image = try XCTUnwrap(Self.image())
        let old = ArtworkLabel(trackID: 1, modified: 1000)

        await disk.store(image, for: .album(10), label: old)
        let saved = await disk.image(for: .album(10), label: old)
        XCTAssertNotNil(saved)
        let otherLabel = await disk.image(for: .album(10), label: ArtworkLabel(trackID: 1, modified: 2000))
        XCTAssertNil(otherLabel, "a changed cover never reads the old file")

        // Music now says the cover changed: pruning deletes the stale file.
        await disk.prune(keeping: LibrarySnapshot.build(tracks: [track(1, modified: 2000)]))
        let afterPrune = await disk.image(for: .album(10), label: old)
        XCTAssertNil(afterPrune)
        XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: directory.path))?.isEmpty ?? true)
    }

    private static func image() -> CGImage? {
        let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        context?.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        return context?.makeImage()
    }
}
