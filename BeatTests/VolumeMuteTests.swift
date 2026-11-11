import XCTest
@testable import Beat

final class VolumeMuteTests: XCTestCase {
    func testMuteRemembersAndRestores() {
        var mute = VolumeMute()
        XCTAssertEqual(mute.toggled(current: 0.7), 0)
        XCTAssertEqual(mute.saved, 0.7)
        XCTAssertEqual(mute.toggled(current: 0), 0.7)
        XCTAssertNil(mute.saved)
    }

    func testUnmutingSilenceThatWasntAMuteUsesTheFallback() {
        var mute = VolumeMute()
        XCTAssertEqual(mute.toggled(current: 0), VolumeMute.fallback, "slider dragged to zero, then unmute")
    }

    func testManualChangeForgetsTheSavedLevel() {
        var mute = VolumeMute()
        _ = mute.toggled(current: 0.9)
        mute.changedManually()
        XCTAssertNil(mute.saved)
        XCTAssertEqual(mute.toggled(current: 0), VolumeMute.fallback, "doesn't jump back to the old 0.9")
    }
}
