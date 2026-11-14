import SwiftUI
import XCTest
@testable import Beat

/// Whole pages over `SnapshotLibrary`, at each device's screen size. The Home page isn't here: its presets count back
/// from today, so it would change day to day; `ElementSnapshotTests` covers its layouts.
@MainActor
final class PageSnapshotTests: XCTestCase {
    private var stores: SnapshotStores!

    override func setUp() async throws {
        stores = try await SnapshotStores.make(for: self)
    }

    /// `page` as the front page of `item`'s stack, opened through the navigator so its cover colours apply.
    private func assertPage<V: View>(_ page: V, in item: SidebarItem, opening route: Route? = nil,
                                     testName: String = #function, line: UInt = #line) {
        stores.navigator.selection = item
        switch route {
        case .album(let id)?: stores.navigator.openAlbum(id)
        case .artist(let id)?: stores.navigator.openArtist(id)
        case .genre(let id)?: stores.navigator.openGenre(id)
        default: break
        }
        assertScreens(NavigationStack { page }, stores: stores, fullScreen: true, testName: testName, line: line)
    }

    func testAlbumPage() { assertPage(AlbumDetailView(albumID: 104), in: .albums, opening: .album(104)) }
    func testArtistPage() { assertPage(ArtistDetailView(artistID: "aurora lane"), in: .artists, opening: .artist("aurora lane")) }
    func testGenrePage() { assertPage(GenreDetailView(genreID: "jazz"), in: .genres, opening: .genre("jazz")) }
    func testLibraryAlbums() { assertPage(AlbumsLibraryView(), in: .albums) }
    func testLibrarySongs() { assertPage(AlbumSongsView(title: "Songs", tracks: SnapshotLibrary.tracks), in: .songs) }
}
