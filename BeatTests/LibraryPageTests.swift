import XCTest
@testable import Beat

final class LibraryPageTests: XCTestCase {
    func testNothingStoredHidesNothing() {
        XCTAssertEqual(LibraryPage.hidden(in: ""), [])
    }

    func testRoundTripKeepsSidebarOrder() {
        let stored = LibraryPage.stored([.genres, .albums])
        XCTAssertEqual(stored, "albums,genres")
        XCTAssertEqual(LibraryPage.hidden(in: stored), [.albums, .genres])
    }

    func testUnknownNamesAreIgnored() {
        XCTAssertEqual(LibraryPage.hidden(in: "songs,playlists,,"), [.songs], "a removed page name mustn't break decoding")
    }

    func testMapsToAndFromSidebarItems() {
        for page in LibraryPage.allCases {
            XCTAssertEqual(LibraryPage(page.item), page)
        }
        XCTAssertNil(LibraryPage(.page(UUID())))
        XCTAssertNil(LibraryPage(nil))
    }
}
