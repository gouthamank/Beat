import AVFoundation
import XCTest
@testable import Beat

final class FolderLibrarySourceTests: XCTestCase {
    // MARK: Parsing tags

    func testIDsAreStableAcrossLaunches() {
        XCTAssertEqual(FolderLibrarySource.stableID(""), 0xCBF2_9CE4_8422_2325, "FNV-1a's starting value")
        XCTAssertEqual(FolderLibrarySource.stableID("/Music/a.mp3"), FolderLibrarySource.stableID("/Music/a.mp3"))
        XCTAssertNotEqual(FolderLibrarySource.stableID("/Music/a.mp3"), FolderLibrarySource.stableID("/Music/b.mp3"))
    }

    func testAlbumKeyIgnoresCaseAndPrefersTheAlbumArtist() {
        let key = FolderLibrarySource.albumKey
        XCTAssertEqual(key("ASC", "Someone", "Out of Space"), key("asc", "Someone Else", "OUT OF SPACE"))
        XCTAssertEqual(key(nil, "ASC", "Out of Space"), key("ASC", nil, "Out of Space"), "the artist when there's no album artist")
        XCTAssertNotEqual(key("ASC", nil, "Out of Space"), key("ASC", nil, "Into the Light"))
        XCTAssertNotEqual(key("AB", nil, "C"), key("A", nil, "BC"), "artist and album don't run together")
    }

    func testYearAndTrackNumber() {
        XCTAssertEqual(FolderLibrarySource.year(from: "2011"), 2011)
        XCTAssertEqual(FolderLibrarySource.year(from: "2011-05-02T00:00:00Z"), 2011)
        XCTAssertEqual(FolderLibrarySource.year(from: nil), 0)
        XCTAssertEqual(FolderLibrarySource.year(from: "unknown"), 0)
        XCTAssertEqual(FolderLibrarySource.trackNumber(from: "3/12"), 3)
        XCTAssertEqual(FolderLibrarySource.trackNumber(from: "7"), 7)
        XCTAssertEqual(FolderLibrarySource.trackNumber(from: nil), 0)
    }

    func testOnlyAudioFilesAreRead() {
        XCTAssertTrue(FolderLibrarySource.isAudio(URL(fileURLWithPath: "/x/Song.MP3")))
        XCTAssertTrue(FolderLibrarySource.isAudio(URL(fileURLWithPath: "/x/Song.flac")))
        XCTAssertFalse(FolderLibrarySource.isAudio(URL(fileURLWithPath: "/x/cover.jpg")))
        XCTAssertFalse(FolderLibrarySource.isAudio(URL(fileURLWithPath: "/x/notes")))
    }

    // MARK: Reading a folder

    func testReadsTheAudioFilesInAFolderAndItsSubfolders() async throws {
        let folder = try temporaryFolder()
        let album = folder.appendingPathComponent("Album", isDirectory: true)
        try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        try Self.writeSilence(to: folder.appendingPathComponent("First.wav"), seconds: 1)
        try Self.writeSilence(to: album.appendingPathComponent("Second.wav"), seconds: 2)
        try Data("not audio".utf8).write(to: folder.appendingPathComponent("notes.txt"))

        let library = try await FolderLibrarySource(folder: folder).load()
        let tracks = library.tracks.sorted { $0.title < $1.title }
        XCTAssertEqual(tracks.map(\.title), ["First", "Second"], "untagged files are named after the file")
        XCTAssertEqual(tracks.map(\.kind), ["WAV", "WAV"])
        XCTAssertEqual(tracks[1].duration, 2, accuracy: 0.05)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Music").path),
                      "an empty Music folder, so Files shows a place to drop songs")

        let again = try await FolderLibrarySource(folder: folder).load()
        XCTAssertEqual(Set(again.tracks.map(\.id)), Set(library.tracks.map(\.id)), "same songs, same IDs")
    }

    func testArtForUnknownSongsIsNilOnceRead() async throws {
        let source = FolderLibrarySource(folder: try temporaryFolder())
        _ = try await source.load()
        let art = await source.artworkData(for: .album(1))
        XCTAssertNil(art)
    }

    /// A short silent WAV file.
    private static func writeSilence(to url: URL, seconds: Double) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        try file.write(from: buffer)
        file.close()
    }
}
