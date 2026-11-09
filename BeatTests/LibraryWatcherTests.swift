import XCTest
@testable import Beat

final class LibraryWatcherTests: XCTestCase {
    private let bundle = "/Users/me/Music/Music/Music Library.musiclibrary"

    func testDatabaseWritesAreRelevant() {
        XCTAssertTrue(LibraryWatcher.isRelevant(paths: ["\(bundle)/Library.musicdb"]))
        XCTAssertTrue(LibraryWatcher.isRelevant(paths: ["\(bundle)/Application.musicdb"]))
        XCTAssertTrue(LibraryWatcher.isRelevant(paths: ["\(bundle)/Extras.itdb"]))
        XCTAssertTrue(LibraryWatcher.isRelevant(paths: ["\(bundle)/sentinel"]))
    }

    func testFinderAndPreferenceNoiseIsIgnored() {
        XCTAssertFalse(LibraryWatcher.isRelevant(paths: ["\(bundle)/.DS_Store"]))
        XCTAssertFalse(LibraryWatcher.isRelevant(paths: ["\(bundle)/Preferences.plist"]))
        XCTAssertFalse(LibraryWatcher.isRelevant(paths: []))
    }

    func testAnyRelevantPathInABatchCounts() {
        XCTAssertTrue(LibraryWatcher.isRelevant(paths: ["\(bundle)/.DS_Store", "\(bundle)/Library.musicdb"]))
    }
}
