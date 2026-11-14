import XCTest
@testable import Beat

@MainActor
final class AppNavigatorTests: XCTestCase {
    private var defaults: UserDefaults!
    private var navigator: AppNavigator!
    /// In memory: the Home page only, never saved.
    private var pages: PageStore!

    override func setUp() async throws {
        defaults = temporaryDefaults()
        navigator = AppNavigator(defaults: defaults)
        pages = PageStore(directory: nil)
    }

    private var home: UUID { pages.tree.nodes[0].id }

    // MARK: Paths

    func testEachSidebarPageKeepsItsOwnPath() {
        navigator.selection = .page(home)
        navigator.openAlbum(1)
        navigator.selection = .albums
        XCTAssertEqual(navigator.path, [], "another page starts at its top level")
        navigator.openArtist("asc")
        navigator.selection = .page(home)
        XCTAssertEqual(navigator.path, [.album(1)], "coming back finds the album still open")
        navigator.selection = .albums
        XCTAssertEqual(navigator.path, [.artist("asc")])
    }

    func testAStackThatIsNotSelectedCannotChangeThePath() {
        navigator.selection = .page(home)
        let homeStack = navigator.pathBinding(for: .page(home))
        navigator.selection = .songs
        navigator.openAlbum(2)
        XCTAssertEqual(homeStack.wrappedValue, [], "it reads as empty while another page is up")
        homeStack.wrappedValue = []
        XCTAssertEqual(navigator.path, [.album(2)], "a torn-down stack clearing its path doesn't wipe the new page's")
        navigator.pathBinding(for: .songs).wrappedValue = []
        XCTAssertEqual(navigator.path, [], "the selected page's own stack does")
    }

    func testOpeningARouteAlreadyInTheTrailGoesBackToIt() {
        navigator.selection = .artists
        navigator.openArtist("asc")
        navigator.openAlbum(1)
        navigator.openArtist("asc")
        XCTAssertEqual(navigator.path, [.artist("asc")])
    }

    func testOpeningAnAlbumAtASongAsksItsPageToHighlightIt() {
        navigator.selection = .page(home)
        navigator.openAlbum(1, highlighting: 10)
        XCTAssertEqual(navigator.path, [.album(1)])
        let first = try! XCTUnwrap(navigator.trackHighlight)
        XCTAssertEqual([first.albumID, first.trackID], [1, 10])
        navigator.openAlbum(1, highlighting: 10)
        XCTAssertEqual(navigator.path, [.album(1)], "the album already in front isn't stacked again")
        XCTAssertNotEqual(navigator.trackHighlight?.token, first.token, "the same song asked again highlights again")
        navigator.trackHighlight = nil
        navigator.openAlbum(2)
        XCTAssertNil(navigator.trackHighlight, "a plain open highlights nothing")
    }

    func testGoingToAnArtistSelectsArtistsWithOnlyThatArtistOpen() {
        navigator.selection = .page(home)
        navigator.openAlbum(1)
        navigator.goTo(.artist("blocks"), in: .artists, hidden: [])
        XCTAssertEqual(navigator.selection, .artists)
        XCTAssertEqual(navigator.path, [.artist("blocks")])
        navigator.selection = .page(home)
        XCTAssertEqual(navigator.path, [.album(1)], "the page you were on keeps its own path")
    }

    func testGoingToAnAlbumOnTheLibraryPageAlreadyShowingReplacesItsPath() {
        navigator.selection = .albums
        navigator.openAlbum(1)
        navigator.openArtist("blocks")
        navigator.goTo(.album(2), in: .albums, hidden: [], highlighting: 20)
        XCTAssertEqual(navigator.selection, .albums)
        XCTAssertEqual(navigator.path, [.album(2)])
        XCTAssertEqual(navigator.trackHighlight?.trackID, 20)
        XCTAssertEqual(navigator.trackHighlight?.albumID, 2)
    }

    func testGoingToAHiddenLibraryPageOpensOnTheCurrentPage() {
        navigator.selection = .page(home)
        navigator.goTo(.genre("rock"), in: .genres, hidden: [.genres])
        XCTAssertEqual(navigator.selection, .page(home))
        XCTAssertEqual(navigator.path, [.genre("rock")])
    }

    func testShowingASongInSongsSelectsSongsAtItsTopLevel() {
        navigator.selection = .songs
        navigator.openArtist("blocks")
        navigator.searches[.songs] = "nothing like it"
        navigator.selection = .page(home)
        navigator.showInSongs(3, album: 8, hidden: [], clearingSearch: true)
        XCTAssertEqual(navigator.selection, .songs)
        XCTAssertEqual(navigator.path, [], "back at the list, not the artist left open on it")
        XCTAssertNil(navigator.searches[.songs], "a search hiding the song is cleared")
        XCTAssertEqual(navigator.songsHighlight?.trackID, 3)
        let first = navigator.songsHighlight?.token
        navigator.showInSongs(3, album: 8, hidden: [], clearingSearch: false)
        XCTAssertNotEqual(navigator.songsHighlight?.token, first, "the same song again highlights again")
    }

    func testShowingASongInHiddenSongsOpensItsAlbum() {
        navigator.selection = .page(home)
        navigator.searches[.songs] = "kept"
        navigator.showInSongs(3, album: 8, hidden: [.songs], clearingSearch: true)
        XCTAssertEqual(navigator.selection, .albums)
        XCTAssertEqual(navigator.path, [.album(8)])
        XCTAssertEqual(navigator.trackHighlight?.trackID, 3)
        XCTAssertNil(navigator.songsHighlight)
        XCTAssertEqual(navigator.searches[.songs], "kept")
    }

    func testGoBack() {
        navigator.selection = .albums
        XCTAssertFalse(navigator.canGoBack)
        navigator.goBack()
        XCTAssertEqual(navigator.path, [], "nothing to go back from")
        navigator.openAlbum(1)
        navigator.push(.element(ElementRoute(pageID: home, elementID: UUID())))
        navigator.goBack()
        XCTAssertEqual(navigator.path, [.album(1)])
        XCTAssertTrue(navigator.canGoBack)
    }

    func testReselectingGoesToTheTopLevelThenScrollsToTheTop() {
        navigator.selection = .albums
        navigator.openAlbum(1)
        navigator.reselect()
        XCTAssertEqual(navigator.path, [])
        XCTAssertNil(navigator.scrollToTop, "a pushed page closing is enough the first time")
        navigator.reselect()
        XCTAssertEqual(navigator.scrollToTop, ScrollToTopRequest(item: .albums, token: 1))
        navigator.reselect()
        XCTAssertEqual(navigator.scrollToTop?.token, 2, "each click asks again")
    }

    // MARK: Restoring the sidebar

    func testRestoresTheSavedPageAndOpensTheFoldersAroundIt() {
        let folder = pages.create(folder: true, in: nil)
        let page = pages.create(folder: false, in: folder)
        navigator.selection = .page(page)

        let next = AppNavigator(defaults: defaults)
        XCTAssertTrue(next.restoreSavedSelection(tree: pages.tree, hidden: []))
        XCTAssertEqual(next.selection, .page(page))
        XCTAssertEqual(next.expandedFolders, [folder])

        let after = AppNavigator(defaults: defaults)
        XCTAssertEqual(after.expandedFolders, [folder], "open folders are saved too")
    }

    func testNothingToRestoreWhenTheSavedPageIsGoneOrHidden() {
        let page = pages.create(folder: false, in: nil)
        navigator.selection = .page(page)
        pages.delete(page)
        XCTAssertFalse(AppNavigator(defaults: defaults).restoreSavedSelection(tree: pages.tree, hidden: []))

        navigator.selection = .genres
        XCTAssertFalse(AppNavigator(defaults: defaults).restoreSavedSelection(tree: pages.tree, hidden: [.genres]))
        XCTAssertTrue(AppNavigator(defaults: defaults).restoreSavedSelection(tree: pages.tree, hidden: [.albums]))
    }

    func testDeletedFoldersAreForgotten() {
        let folder = pages.create(folder: true, in: nil)
        navigator.expandedFolders = [folder, UUID()]
        _ = navigator.restoreSavedSelection(tree: pages.tree, hidden: [])
        XCTAssertEqual(navigator.expandedFolders, [folder])
    }

    // MARK: Creating and naming

    func testANewPageIsSelectedAndCancellingItsNameRemovesIt() {
        navigator.selection = .page(home)
        navigator.create(folder: false, in: pages)
        guard case .page(let new)? = navigator.selection, new != home else { return XCTFail("the new page is selected") }
        XCTAssertEqual(navigator.renaming, new)
        XCTAssertEqual(pages.tree.nodes.map(\.id), [home, new], "below the selected page")

        navigator.cancelNaming(in: pages)
        XCTAssertNil(pages.node(new))
        XCTAssertEqual(navigator.selection, .page(home), "back where things were")
        XCTAssertNil(navigator.namingNew)
    }

    func testANewFolderIsNamedWithoutChangingTheSelection() {
        navigator.selection = .songs
        navigator.create(folder: true, in: pages)
        XCTAssertEqual(navigator.selection, .songs)
        let folder = try? XCTUnwrap(navigator.renaming)
        XCTAssertEqual(pages.node(folder ?? UUID())?.isFolder, true)
        XCTAssertEqual(pages.tree.nodes.last?.id, folder, "at the end of the top level")
    }
}
