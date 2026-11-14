import XCTest
@testable import Beat

/// The UI tests' songs (`Fixtures/Library`, written by `Fixtures/make-library.swift`), read as a UI-test launch reads
/// them: if the files or the tag reading break, this fails before any UI test does.
final class FixtureLibraryTests: XCTestCase {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Library", isDirectory: true)

    func testReadsEverySongWithItsTags() async throws {
        let library = try await FolderLibrarySource(folder: Self.folder, makesMusicFolder: false).load()
        XCTAssertEqual(library.tracks.count, 31)
        XCTAssertEqual(library.albums.count, 9)
        XCTAssertEqual(Set(library.artists.map(\.name)), ["Aurora Lane", "Bronze Era", "Cobalt", "Delta Hours"])
        XCTAssertEqual(Set(library.genres.map(\.name)), ["Ambient", "Electronic", "Jazz", "Rock"])

        let song = try XCTUnwrap(library.tracks.first { $0.title == "Polar Night" })
        XCTAssertEqual(song.artist, "Aurora Lane")
        XCTAssertEqual(song.albumArtist, "Aurora Lane")
        XCTAssertEqual(song.album, "Northern Lights")
        XCTAssertEqual(song.genre, "Electronic")
        XCTAssertEqual(song.year, 2019)
        XCTAssertEqual(song.trackNumber, 2, "from the MP4 track tag")
        XCTAssertEqual(song.duration, 2, accuracy: 0.1)
        XCTAssertTrue(song.hasArtwork)
    }

    func testEveryAlbumHasItsCover() async throws {
        let source = FolderLibrarySource(folder: Self.folder, makesMusicFolder: false)
        let library = try await source.load()
        for album in library.albums {
            let art = await source.artworkData(for: .album(album.id))
            XCTAssertNotNil(art, album.title)
        }
    }

    func testReadingLeavesTheFolderAlone() async throws {
        _ = try await FolderLibrarySource(folder: Self.folder, makesMusicFolder: false).load()
        XCTAssertFalse(FileManager.default.fileExists(atPath: Self.folder.appendingPathComponent("Music").path),
                       "no Music folder made in the repo")
    }
}

final class LaunchOptionsTests: XCTestCase {
    func testFixtureLibraryArgument() {
        XCTAssertEqual(LaunchOptions.fixtureLibrary(in: ["Beat", "-BeatFixtureLibrary", "/tmp/songs"])?.path, "/tmp/songs")
        XCTAssertNil(LaunchOptions.fixtureLibrary(in: ["Beat"]), "an ordinary launch")
        XCTAssertNil(LaunchOptions.fixtureLibrary(in: ["Beat", "-BeatFixtureLibrary"]), "no folder given")
    }

    func testIsolatedOnlyAsTheUITestBuildWithEveryFolderInTheTemporaryHome() {
        let inside = URL(fileURLWithPath: "/tmp/BeatUITests-1/Library/Application Support")
        func problem(app: String? = "dev.gouthaman.Beat.uitest", home: String? = "/tmp/BeatUITests-1", exists: Bool = true,
                     folders: [URL?]) -> String? {
            LaunchOptions.isolationProblem(bundleID: app, home: home, homeExists: exists, dataFolders: folders)
        }
        XCTAssertNil(problem(folders: [inside, URL(fileURLWithPath: "/tmp/BeatUITests-1/Library/Caches")]))
        XCTAssertNotNil(problem(app: "dev.gouthaman.Beat", folders: [inside]), "the real app: its settings are the user's")
        XCTAssertNotNil(problem(app: nil, folders: [inside]))
        XCTAssertNotNil(problem(home: nil, folders: [inside]), "no temporary home")
        XCTAssertNotNil(problem(home: "", folders: [inside]))
        XCTAssertNotNil(problem(folders: [inside, URL(fileURLWithPath: "/Users/me/Library/Caches")]), "one real folder is enough to stop")
        XCTAssertNotNil(problem(folders: [URL(fileURLWithPath: "/tmp/BeatUITests-1-other/Library")]),
                        "a sibling folder whose name starts the same isn't inside")
        XCTAssertNotNil(problem(folders: [nil]), "a folder that couldn't be found")
        XCTAssertNotNil(problem(exists: false, folders: [inside]), "a home made after launch is too late for settings")
        XCTAssertNotNil(problem(home: "/Users/me", folders: [URL(fileURLWithPath: "/Users/me/Library/Caches")]),
                        "a fresh start deletes inside the home, so it must be in /tmp")
        XCTAssertNil(problem(home: "/private/tmp/BeatUITests-1", folders: [URL(fileURLWithPath: "/private/tmp/BeatUITests-1/Library")]))
    }
}
