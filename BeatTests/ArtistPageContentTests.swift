import XCTest
@testable import Beat

final class ArtistPageContentTests: XCTestCase {
    /// ASC: a 10-track LP (2013), a 2-track single (2015), an older LP (2009); a compilation with an ASC
    /// track; another artist's album featuring ASC; and one by "ASCII", which mustn't count.
    private func library() -> LibrarySnapshot {
        var tracks: [Track] = []
        func add(_ count: Int, album: String, id albumID: PersistentID, artist: String, albumArtist: String,
                 year: Int, duration: TimeInterval = 300, compilation: Bool = false, plays: Int = 0) {
            for i in 0..<count {
                tracks.append(.fixture(id: albumID * 100 + PersistentID(i), title: "\(album) \(i)", album: album, albumID: albumID,
                                       artist: artist, albumArtist: albumArtist, track: i + 1, compilation: compilation,
                                       year: year, playCount: i == 0 ? plays : 0, duration: duration))
            }
        }
        add(10, album: "Auxcast", id: 1, artist: "ASC", albumArtist: "ASC", year: 2013, plays: 5)
        add(2, album: "Single", id: 2, artist: "ASC", albumArtist: "ASC", year: 2015, duration: 200, plays: 40)
        add(9, album: "Early", id: 3, artist: "ASC", albumArtist: "ASC", year: 2009)
        add(1, album: "Comp", id: 4, artist: "ASC", albumArtist: "Various Artists", year: 2014, compilation: true)
        add(1, album: "Guest", id: 5, artist: "Other feat. ASC", albumArtist: "Other", year: 2016)
        add(1, album: "Nope", id: 6, artist: "ASCII", albumArtist: "ASCII", year: 2017)
        return .build(tracks: tracks)
    }

    private func content(history: [PersistentID: PlayHistoryStore.Stats] = [:]) throws -> ArtistPageContent {
        let snapshot = library()
        let artist = try XCTUnwrap(snapshot.artistsByID["asc"])
        return ArtistPageContent.build(artist: artist, snapshot: snapshot, history: history)
    }

    func testAlbumsAndShortReleasesNewestFirst() throws {
        let c = try content()
        XCTAssertEqual(c.albums.map(\.title), ["Auxcast", "Early"])
        XCTAssertEqual(c.singlesAndEPs.map(\.title), ["Single"])
        XCTAssertEqual(c.songCount, 21)
    }

    func testTopSongsUseCombinedPlays() throws {
        XCTAssertEqual(try content().topSongs.map(\.title), ["Single 0", "Auxcast 0"])
        // Beat's own plays push the LP track ahead.
        let boosted = try content(history: [100: PlayHistoryStore.Stats(playCount: 50)])
        XCTAssertEqual(boosted.topSongs.first?.title, "Auxcast 0")
        XCTAssertEqual(boosted.plays, 95)
    }

    func testFeaturedAlbumIsMostPlayed() throws {
        XCTAssertEqual(try content().featuredAlbumID, 2)
        // The sidebar's tint uses the same function, so the page and sidebar agree.
        let snapshot = library()
        let artist = try XCTUnwrap(snapshot.artistsByID["asc"])
        XCTAssertEqual(ArtistPageContent.featuredAlbumID(artist: artist, snapshot: snapshot, history: [:]), 2)
        XCTAssertEqual(ArtistPageContent.featuredAlbumID(artist: artist, snapshot: snapshot, history: [100: .init(playCount: 99)]), 1,
                       "Beat's plays count too")
    }

    func testAppearsOnFindsCreditsButNotPartialNames() throws {
        XCTAssertEqual(Set(try content().appearsOn.map(\.title)), ["Comp", "Guest"])
    }

    func testSectionsFollowTheirOwnSorts() throws {
        let snapshot = library()
        let artist = try XCTUnwrap(snapshot.artistsByID["asc"])
        var sorts = ArtistSorts()
        sorts.albums = SortKey(field: .field(.year), ascending: true)
        sorts.appearsOn = SortKey(field: .field(.album), ascending: true)
        let c = ArtistPageContent.build(artist: artist, snapshot: snapshot, history: [:], sorts: sorts)
        XCTAssertEqual(c.albums.map(\.title), ["Early", "Auxcast"], "oldest first")
        XCTAssertEqual(c.appearsOn.map(\.title), ["Comp", "Guest"], "A to Z")

        // Plays sum over each album's tracks, Beat's history included.
        sorts.albums = SortKey(field: .field(.playCount), ascending: false)
        let byPlays = ArtistPageContent.build(artist: artist, snapshot: snapshot, history: [300: PlayHistoryStore.Stats(playCount: 9)], sorts: sorts)
        XCTAssertEqual(byPlays.albums.map(\.title), ["Early", "Auxcast"])
    }

    func testSortsSaveAndFallBack() {
        var sorts = ArtistSorts()
        sorts.singlesAndEPs = SortKey(field: .random, ascending: true)
        XCTAssertEqual(ArtistSorts.decode(sorts.encoded(), customFields: []), sorts)
        XCTAssertEqual(ArtistSorts.decode(Data("junk".utf8), customFields: []), ArtistSorts(), "unreadable falls back to newest first")
        XCTAssertEqual(ArtistSorts.decode(nil, customFields: []).albums, ArtistSorts.newestFirst)
    }

    func testCreditMatching() {
        XCTAssertTrue(ArtistCredits.matches(trackArtist: "Lynx feat. Kemo", name: "Kemo"))
        XCTAssertTrue(ArtistCredits.matches(trackArtist: "Calibre & Marcus Intalex", name: "marcus intalex"))
        XCTAssertTrue(ArtistCredits.matches(trackArtist: "dBridge x Skeptical", name: "Skeptical"))
        XCTAssertTrue(ArtistCredits.matches(trackArtist: "Bjork", name: "Björk"), "accents ignored")
        XCTAssertFalse(ArtistCredits.matches(trackArtist: "Anna", name: "Ann"))
        XCTAssertFalse(ArtistCredits.matches(trackArtist: "Anna & Bob", name: "Ann"))
    }
}
