import XCTest
@testable import Beat

final class ArtistInfoTests: XCTestCase {
    func testMarkupBecomesPlainText() {
        let profile = "Member of [a=Instra:mental] and runs [l=Auxiliary]. See [url=https://example.com]his site[/url]. [b]Bold[/b] [a123]and [r=45678]more."
        XCTAssertEqual(DiscogsMarkup.plainText(profile), "Member of Instra:mental and runs Auxiliary. See his site. Bold and more.")
    }

    func testReferencesByIDBecomeMemberNames() throws {
        XCTAssertEqual(DiscogsMarkup.plainText("made up of [a111] & [a=Truthos Mufasa (2)]", names: [111: "Amos Childs"]),
                       "made up of Amos Childs & Truthos Mufasa")
        let json = #"{"id": 7, "name": "A/T/O/S", "profile": "A duo made up of [a111] & [a222]. With [a999].", "members": [{"id": 111, "name": "Amos Childs"}, {"id": 222, "name": "Truthos Mufasa (2)"}]}"#
        let artist = try JSONDecoder().decode(DiscogsArtist.self, from: Data(json.utf8))
        XCTAssertEqual(artist.plainProfile, "A duo made up of Amos Childs & Truthos Mufasa. With .",
                       "known IDs become names; an unknown one is dropped")
    }

    @MainActor
    func testArtistImagesAnswerOncePerArtistUntilRefreshed() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let images = ArtistImages(directory: directory)
        XCTAssertNil(images.photo(for: "asc"), "no photo saved: the mosaic")

        let file = try XCTUnwrap(ArtistInfoProvider.photoURL(forKey: "asc", in: directory))
        try TestImages.png(width: 1).write(to: file)
        XCTAssertNil(images.photo(for: "asc"), "the answer stays put, so nothing changes under a view")
        images.refresh("asc")
        let photo = images.photo(for: "asc")
        XCTAssertNotNil(photo, "after a refresh, the downloaded photo")
        images.refresh("asc")
        XCTAssertTrue(images.photo(for: "asc") === photo, "refreshing an unchanged photo keeps the same image")
        images.clear()
        try FileManager.default.removeItem(at: file)
        XCTAssertNil(images.photo(for: "asc"))
    }

    func testChoosingAnArtistWithoutAPhotoRemovesTheOldPhoto() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubDiscogs.self]
        let provider = ArtistInfoProvider(directory: directory, session: URLSession(configuration: configuration))
        let file = try XCTUnwrap(ArtistInfoProvider.photoURL(forKey: "asc", in: directory))

        let first = await provider.choose(id: 1, key: "asc", token: "t")
        XCTAssertEqual(first?.photo, file)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "the first match's photo is saved")

        let second = await provider.choose(id: 2, key: "asc", token: "t")
        XCTAssertEqual(second?.artist.id, 2)
        XCTAssertNil(second?.photo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "the wrong artist's photo is gone")
    }

    func testMatcherAcceptsOnlyExactNames() {
        let results = [
            DiscogsSearchResult(id: 1, title: "ASC Collective"),
            DiscogsSearchResult(id: 2, title: "ASC (2)"),
            DiscogsSearchResult(id: 3, title: "ASC"),
        ]
        XCTAssertEqual(ArtistMatcher.best(results, name: "asc")?.id, 2, "first exact match, suffix ignored")
        XCTAssertNil(ArtistMatcher.best([DiscogsSearchResult(id: 1, title: "ASC Collective")], name: "ASC"))
        XCTAssertEqual(ArtistMatcher.best([DiscogsSearchResult(id: 9, title: "Björk")], name: "Bjork")?.id, 9)
        XCTAssertEqual(ArtistMatcher.baseName("Nirvana (2)"), "Nirvana")
    }

    func testDecodesDiscogsArtist() throws {
        let json = """
        {"id": 42, "name": "ASC", "realname": "James Clements", "profile": "[b]Hi[/b]",
         "urls": ["https://asc.bandcamp.com"], "members": [{"id": 1, "name": "A", "active": true}],
         "images": [{"type": "secondary", "uri": "https://img/2.jpg"}, {"type": "primary", "uri": "https://img/1.jpg"}],
         "uri": "https://www.discogs.com/artist/42-ASC", "extra": 1}
        """
        let artist = try JSONDecoder().decode(DiscogsArtist.self, from: Data(json.utf8))
        XCTAssertEqual(artist.realname, "James Clements")
        XCTAssertEqual(artist.primaryImageURL?.absoluteString, "https://img/1.jpg")
        XCTAssertNil(artist.groups)
    }

    func testCacheFreshness() {
        let now = Date()
        XCTAssertFalse(CachedArtistInfo(artist: nil, fetchedAt: now.addingTimeInterval(-31 * 86_400)).isFresh(now: now))
        XCTAssertTrue(CachedArtistInfo(artist: nil, fetchedAt: now.addingTimeInterval(-3 * 86_400)).isFresh(now: now))
        let found = DiscogsArtist(id: 1, name: "A")
        XCTAssertTrue(CachedArtistInfo(artist: found, fetchedAt: now.addingTimeInterval(-400 * 86_400)).isFresh(now: now))
    }

    func testRequestsCarryTokenAndUserAgent() throws {
        let request = try XCTUnwrap(ArtistInfoProvider.searchRequest(name: "ASC", token: "abc"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Discogs token=abc")
        XCTAssertNotNil(request.value(forHTTPHeaderField: "User-Agent"))
        XCTAssertEqual(request.url?.host, "api.discogs.com")
    }
}

/// Discogs for `ArtistInfoProvider` tests: artist 1 has a photo, artist 2 has none.
private final class StubDiscogs: URLProtocol, @unchecked Sendable {
    private static let bodies: [String: String] = [
        "/artists/1": #"{"id": 1, "name": "ASC", "images": [{"type": "primary", "uri": "https://img.example/1.jpg"}]}"#,
        "/artists/2": #"{"id": 2, "name": "ASC (2)"}"#,
        "/1.jpg": "not really a jpeg",
    ]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let body = Self.bodies[url.path]
        let response = HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? "").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
