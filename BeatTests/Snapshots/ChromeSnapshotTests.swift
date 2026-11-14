import SwiftUI
import XCTest
@testable import Beat

/// The app around the pages: the now-playing bar, Now Playing, the sidebar and the element editor.
@MainActor
final class ChromeSnapshotTests: XCTestCase {
    private var stores: SnapshotStores!

    override func setUp() async throws {
        stores = try await SnapshotStores.make(for: self)
    }

    /// Northern Lights from its second song, playing (the player is a stand-in: nothing sounds).
    private func play() -> Track {
        stores.queue.play(SnapshotLibrary.tracks.filter { $0.albumID == 101 }, startAt: 1)
        return stores.queue.current!
    }

    func testNowPlayingBar() {
        _ = play()
        assertScreens(NowPlayingBar().padding(.vertical, 12), stores: stores)
    }

    func testNowPlaying() {
        let track = play()
        assertScreens(NowPlayingView(track: track, defaults: stores.defaults), stores: stores, fullScreen: true)
    }

    func testSidebar() {
        let home = stores.pages.tree.nodes[0].id
        stores.navigator.selection = .page(home)
        assertScreens(SidebarView(selection: .constant(.page(home))), stores: stores, fullScreen: true, width: 280)
    }

    func testElementEditor() {
        let home = stores.pages.tree.nodes[0].id
        let filter = SmartFilter(id: UUID(uuidString: "00000000-0000-0000-0000-0000000000E1")!, name: "Recent Jazz",
                                 output: .albums,
                                 steps: [.filter(RuleGroup(match: .all, nodes: [.rule(Rule(field: .genre, op: .is, value: .text("Jazz")))])),
                                         .sort([SortKey(field: .field(.year), ascending: false)]),
                                         .limit(Limit(count: 10, unit: .albums))])
        let draft = ElementDraft(target: .page(home), element: PageElement(filter: filter))
        assertScreens(FilterEditorSheet(draft: draft), stores: stores, fullScreen: true)
    }
}
