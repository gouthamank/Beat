import XCTest
@testable import Beat

final class QuickOpenIndexTests: XCTestCase {
    private let tracks: [Track] = [
        .fixture(id: 1, title: "Seems Like", album: "FABRICLIVE.50", albumID: 50, artist: "dBridge", albumArtist: "dBridge x Instra:mental"),
        .fixture(id: 2, title: "Encke Gap", album: "FABRICLIVE.50", albumID: 50, artist: "Instra:mental", albumArtist: "dBridge x Instra:mental", track: 2),
        .fixture(id: 3, title: "Séance", album: "Séance EP", albumID: 8, artist: "Blocks", albumArtist: "Blocks", genre: "Drum & Bass"),
        .fixture(id: 4, title: "Moon & Stars", album: "Séance EP", albumID: 8, artist: "Blocks", albumArtist: "Blocks", track: 2, genre: "Drum & Bass"),
        .fixture(id: 5, title: "Blockbuster", album: "Singles", albumID: 9, artist: "Someone", albumArtist: "Someone"),
    ]

    private let homeID = UUID()
    private let auxID = UUID()

    private var tree: PageTree {
        var home = SidebarNode.page("Home")
        home.id = homeID
        var aux = SidebarNode.page("Auxiliary")
        aux.id = auxID
        return PageTree(nodes: [home, .folder("Deep", [.folder("DnB", [aux])])])
    }

    private func index(libraryPages: [LibraryPage] = LibraryPage.allCases) -> QuickOpenIndex {
        QuickOpenIndex(snapshot: .build(tracks: tracks), tree: tree, libraryPages: libraryPages)
    }

    private func targets(_ groups: [QuickOpenGroup], _ kind: QuickOpenItem.Kind) -> [QuickOpenItem.Target] {
        groups.first { $0.kind == kind }?.items.map(\.target) ?? []
    }

    func testEmptyQueryFindsNothing() {
        XCTAssertEqual(index().results(for: "  "), [])
    }

    func testEveryWordMustMatchAndAccentsAreIgnored() {
        let groups = index().results(for: "seance")
        XCTAssertEqual(targets(groups, .album), [.album(8)])
        XCTAssertEqual(targets(groups, .song), [.song(3, album: 8), .song(4, album: 8)], "Séance by its title, Moon & Stars by its album")
        XCTAssertEqual(targets(index().results(for: "blocks moon"), .song), [.song(4, album: 8)])
    }

    func testNamesStartingWithTheQueryComeBeforeOtherMatches() {
        let songs = targets(index().results(for: "block"), .song)
        // Blockbuster's title starts with it; the Blocks songs only match on their artist.
        XCTAssertEqual(songs.first, .song(5, album: 9))
        XCTAssertEqual(Set(songs.dropFirst()), [.song(3, album: 8), .song(4, album: 8)])
    }

    func testGroupWithTheBestMatchComesFirst() {
        let groups = index().results(for: "blocks")
        XCTAssertEqual(groups.first?.kind, .artist, "the artist named exactly that leads, ahead of the songs")
        XCTAssertEqual(targets(groups, .artist), [.artist("blocks")])
    }

    func testPagesAndLibraryPages() {
        let groups = index().results(for: "aux")
        XCTAssertEqual(targets(groups, .page), [.sidebar(.page(auxID))])
        let aux = groups.first { $0.kind == .page }?.items.first
        XCTAssertEqual(aux?.subtitle, "Deep ▸ DnB", "a page shows the folders it's in")
        XCTAssertEqual(targets(index().results(for: "dnb"), .page), [.sidebar(.page(auxID))],
                       "no folders, but the page inside by its folder's name")
        XCTAssertEqual(targets(index().results(for: "deep aux"), .page), [.sidebar(.page(auxID))], "found by its folders' names too")
        XCTAssertEqual(targets(index().results(for: "genres"), .page), [.sidebar(.genres)])
        XCTAssertEqual(targets(index(libraryPages: [.albums]).results(for: "genres"), .page), [], "a hidden Library page isn't offered")
    }

    func testEachKindIsLimited() {
        let many = (1...20).map { Track.fixture(id: PersistentID($0), title: "Song \($0)", albumID: PersistentID($0)) }
        let groups = QuickOpenIndex(snapshot: .build(tracks: many), tree: PageTree(), libraryPages: []).results(for: "song")
        XCTAssertEqual(targets(groups, .song).count, QuickOpenIndex.limits[.song])
    }

    func testShorterNamesFirstWhenEquallyGood() {
        let songs = [Track.fixture(id: 1, title: "The Gap Year", albumID: 1), .fixture(id: 2, title: "Big Gap", albumID: 2)]
        let groups = QuickOpenIndex(snapshot: .build(tracks: songs), tree: PageTree(), libraryPages: []).results(for: "gap")
        XCTAssertEqual(targets(groups, .song), [.song(2, album: 2), .song(1, album: 1)])
    }

    func testWordStarts() {
        XCTAssertTrue(QuickOpenIndex.startsWord("gap", in: "encke gap"))
        XCTAssertTrue(QuickOpenIndex.startsWord("feat", in: "haven (feat. jennifer hall)"))
        XCTAssertFalse(QuickOpenIndex.startsWord("ap", in: "encke gap"))
        XCTAssertTrue(QuickOpenIndex.startsWord("ap", in: "gap ap"), "a later occurrence can start a word")
    }
}

final class QuickOpenActionTests: XCTestCase {
    private func resolve(_ target: QuickOpenItem.Target, song: QuickOpenSongAction = .album,
                         album: QuickOpenAlbumAction = .open, alternate: Bool = false) -> QuickOpenAction {
        QuickOpenAction.resolve(target, song: song, album: album, alternate: alternate)
    }

    func testSongsFollowTheSettingAndOptionReturnDoesTheOther() {
        let song = QuickOpenItem.Target.song(3, album: 8)
        XCTAssertEqual(resolve(song), .go(.album(8), in: .albums, highlighting: 3))
        XCTAssertEqual(resolve(song, alternate: true), .playAlbum(8, from: 3))
        XCTAssertEqual(resolve(song, song: .songs), .showInSongs(3, album: 8))
        XCTAssertEqual(resolve(song, song: .songs, alternate: true), .playAlbum(8, from: 3))
        XCTAssertEqual(resolve(song, song: .play), .playAlbum(8, from: 3))
        XCTAssertEqual(resolve(song, song: .play, alternate: true), .go(.album(8), in: .albums, highlighting: 3),
                       "set to play, ⌥Return opens the album")
    }

    func testAlbumsFollowTheSettingAndOptionReturnDoesTheOther() {
        XCTAssertEqual(resolve(.album(8)), .go(.album(8), in: .albums, highlighting: nil))
        XCTAssertEqual(resolve(.album(8), alternate: true), .playAlbum(8, from: nil))
        XCTAssertEqual(resolve(.album(8), album: .play), .playAlbum(8, from: nil))
        XCTAssertEqual(resolve(.album(8), album: .play, alternate: true), .go(.album(8), in: .albums, highlighting: nil))
    }

    func testOtherResultsIgnoreTheSettingsAndOption() {
        for alternate in [false, true] {
            XCTAssertEqual(resolve(.artist("blocks"), song: .play, album: .play, alternate: alternate),
                           .go(.artist("blocks"), in: .artists, highlighting: nil))
            XCTAssertEqual(resolve(.genre("rock"), alternate: alternate), .go(.genre("rock"), in: .genres, highlighting: nil))
            XCTAssertEqual(resolve(.sidebar(.songs), alternate: alternate), .select(.songs))
        }
    }
}

@MainActor
final class QuickOpenModelTests: XCTestCase {
    func testArrowsMoveThroughResultsAndStopAtTheEnds() async throws {
        let tracks = (1...3).map { Track.fixture(id: PersistentID($0), title: "Song \($0)", albumID: PersistentID($0)) }
        let model = QuickOpenModel()
        model.open(snapshot: .build(tracks: tracks), version: 1, tree: PageTree(), libraryPages: [])
        model.query = "song"
        for _ in 0..<300 where model.groups.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        let songs = model.items.map(\.target).filter { if case .song = $0 { true } else { false } }
        XCTAssertEqual(songs.count, 3)
        XCTAssertEqual(model.selected, model.items.first?.target, "the first result is ready for Return")
        model.move(-1)
        XCTAssertEqual(model.selected, model.items.first?.target)
        for _ in 0..<10 { model.move(1) }
        XCTAssertEqual(model.selected, model.items.last?.target)
        XCTAssertEqual(model.scrollTarget, model.selected, "the keyboard scrolls the list")
    }

    func testOpeningAgainStartsAfresh() async throws {
        let model = QuickOpenModel()
        model.open(snapshot: .build(tracks: [.fixture(id: 1, title: "Song")]), version: 1, tree: PageTree(), libraryPages: [])
        model.query = "song"
        for _ in 0..<300 where model.groups.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        model.open(snapshot: .build(tracks: [.fixture(id: 1, title: "Song")]), version: 1, tree: PageTree(), libraryPages: [])
        XCTAssertEqual(model.query, "")
        XCTAssertTrue(model.groups.isEmpty)
        XCTAssertNil(model.selected)
    }
}
