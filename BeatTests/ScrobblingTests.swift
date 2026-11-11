import XCTest
@testable import Beat

final class ScrobblingTests: XCTestCase {
    private let credentials = LastFMCredentials(apiKey: "key", secret: "secret")
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func scrobble(_ title: String = "Song", at date: Date? = nil) -> Scrobble {
        Scrobble(.fixture(id: 1, title: title), startedAt: date ?? start)!
    }

    // MARK: Signing

    func testSignatureSortsParametersAndSkipsFormat() {
        let request = LastFMRequest.getToken(credentials)
        XCTAssertEqual(request.parameters["api_sig"], "b4705499705a550b07ca058a15bde9b0",
                       "md5 of api_keykeymethodauth.getToken + secret")
        XCTAssertEqual(request.parameters["format"], "json")
        XCTAssertEqual(LastFMRequest.signature(["method": "auth.getToken", "api_key": "key", "format": "json"], secret: "secret"),
                       "b4705499705a550b07ca058a15bde9b0", "format isn't signed, and order doesn't matter")
    }

    func testSignatureUsesByteOrder() {
        // "albumArtist[0]" sorts before "album[0]": "A" (0x41) comes before "[" (0x5B).
        let parameters = ["album[0]": "Y", "albumArtist[0]": "X", "method": "track.scrobble", "api_key": "key", "sk": "session"]
        XCTAssertEqual(LastFMRequest.signature(parameters, secret: "secret"), "a69cbdd0b55c04552d73f9e9c9996cb2")
    }

    func testFormBodyEncodesEverythingButUnreserved() {
        XCTAssertEqual(LastFMRequest.formBody(["track": "Björk & Co", "a": "x/y"]), "a=x%2Fy&track=Bj%C3%B6rk%20%26%20Co")
    }

    func testPlaceholderOrMissingKeyMeansNoLastFM() {
        XCTAssertNil(LastFMCredentials.make(apiKey: nil, secret: "s"))
        XCTAssertNil(LastFMCredentials.make(apiKey: "", secret: "s"))
        XCTAssertNil(LastFMCredentials.make(apiKey: "your_api_key", secret: "your_shared_secret"), "the example file, unedited")
        XCTAssertEqual(LastFMCredentials.make(apiKey: "k", secret: "s"), LastFMCredentials(apiKey: "k", secret: "s"))
    }

    // MARK: Requests

    func testScrobbleBatchIndexesFields() {
        let first = scrobble("One")
        var second = scrobble("Two")
        second.album = ""
        second.trackNumber = 0
        let p = LastFMRequest.scrobble([first, second], sessionKey: "sk1", credentials).parameters
        XCTAssertEqual(p["method"], "track.scrobble")
        XCTAssertEqual(p["sk"], "sk1")
        XCTAssertEqual(p["track[0]"], "One")
        XCTAssertEqual(p["track[1]"], "Two")
        XCTAssertEqual(p["timestamp[0]"], "1800000000")
        XCTAssertEqual(p["album[0]"], "Album")
        XCTAssertNil(p["album[1]"], "empty album left out")
        XCTAssertNil(p["trackNumber[1]"], "no track number left out")
        XCTAssertNil(p["albumArtist[0]"], "same as the artist, so left out")
    }

    func testScrobbleRequestTakesAtMostFifty() {
        let batch = (0..<60).map { scrobble("\($0)") }
        let p = LastFMRequest.scrobble(batch, sessionKey: "sk", credentials).parameters
        XCTAssertNotNil(p["track[49]"])
        XCTAssertNil(p["track[50]"])
    }

    func testNowPlayingHasNoTimestamp() {
        let p = LastFMRequest.nowPlaying(scrobble(), sessionKey: "sk", credentials).parameters
        XCTAssertEqual(p["method"], "track.updateNowPlaying")
        XCTAssertEqual(p["track"], "Song")
        XCTAssertNil(p["timestamp"])
    }

    func testApprovalURL() throws {
        let url = try XCTUnwrap(LastFMRequest.approvalURL(token: "t1", apiKey: "key"))
        XCTAssertEqual(url.absoluteString, "https://www.last.fm/api/auth/?api_key=key&token=t1")
    }

    // MARK: Answers

    func testAnswersAreClassified() {
        func answer(_ json: String, status: Int = 200) -> LastFMResult<LastFMRequest.Accepted> {
            let response = HTTPURLResponse(url: LastFMRequest.endpoint, statusCode: status, httpVersion: nil, headerFields: nil)
            return LastFMRequest.result(LastFMRequest.Accepted.self, data: Data(json.utf8), response: response)
        }
        guard case .success = answer(#"{"scrobbles": {"@attr": {"accepted": 1, "ignored": 0}}}"#) else { return XCTFail("success") }
        guard case .badSession = answer(#"{"error": 9, "message": "Invalid session key"}"#) else { return XCTFail("9") }
        for code in [11, 16, 29] {
            guard case .retryLater = answer(#"{"error": \#(code), "message": "Busy"}"#) else { return XCTFail("\(code)") }
        }
        guard case .failed(code: 14, message: _) = answer(#"{"error": 14, "message": "Unauthorized Token"}"#) else { return XCTFail("14") }
        guard case .retryLater = answer("<html>Bad gateway</html>", status: 502) else { return XCTFail("5xx") }
    }

    func testSessionAnswerDecodes() {
        let json = #"{"session": {"name": "gk", "key": "abc", "subscriber": 0}}"#
        guard case .success(let answer) = LastFMRequest.result(LastFMRequest.SessionAnswer.self, data: Data(json.utf8), response: nil)
        else { return XCTFail() }
        XCTAssertEqual(answer.session.name, "gk")
        XCTAssertEqual(answer.session.key, "abc")
    }

    // MARK: Queue

    func testEligibility() {
        XCTAssertNil(Scrobble(.fixture(id: 1, duration: 30), startedAt: start), "30 seconds or less")
        XCTAssertNotNil(Scrobble(.fixture(id: 1, duration: 31), startedAt: start))
        XCTAssertNil(Scrobble(.fixture(id: 1, title: " "), startedAt: start), "no title")
        XCTAssertNil(Scrobble(.fixture(id: 1, artist: "", albumArtist: ""), startedAt: start), "no artist")
        let fallback = Scrobble(.fixture(id: 1, artist: "", albumArtist: "ASC"), startedAt: start)
        XCTAssertEqual(fallback?.artist, "ASC", "album artist stands in for a missing artist")
        XCTAssertEqual(fallback?.albumArtist, "")
        XCTAssertEqual(Scrobble(.fixture(id: 1, artist: "A", albumArtist: "Various"), startedAt: start)?.albumArtist, "Various")
    }

    func testQueueBatchesRemovesAndExpires() throws {
        var queue = ScrobbleQueue()
        for i in 0..<60 { queue.enqueue(scrobble("\(i)")) }
        let batch = queue.nextBatch
        XCTAssertEqual(batch.count, 50)
        XCTAssertEqual(batch.first?.track, "0")
        queue.enqueue(scrobble("late"))
        queue.remove(batch)
        XCTAssertEqual(queue.pending.map(\.track), (50..<60).map { "\($0)" } + ["late"], "only what was sent goes")

        queue.enqueue(scrobble("old", at: start.addingTimeInterval(-15 * 86_400)))
        queue.dropExpired(now: start)
        XCTAssertFalse(queue.pending.contains { $0.track == "old" }, "Last.fm refuses scrobbles over 14 days old")

        let decoded = try JSONDecoder().decode(ScrobbleQueue.self, from: JSONEncoder().encode(queue))
        XCTAssertEqual(decoded, queue)
    }

    // MARK: Sending

    @MainActor
    private func makeScrobbler(stub: URLProtocol.Type, directory: URL) -> Scrobbler {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: LastFMSettings.enabledKey)
        defaults.set("gk", forKey: LastFMSettings.usernameKey)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [stub]
        return Scrobbler(credentials: credentials, fileURL: directory.appendingPathComponent("scrobbles.json"),
                         session: URLSession(configuration: configuration), defaults: defaults,
                         storage: .init(load: { "session" }, save: { _ in }))
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
    }

    @MainActor
    func testPlaysAreSentAndLeaveTheQueue() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scrobbler = makeScrobbler(stub: StubLastFMAccepts.self, directory: directory)
        XCTAssertEqual(scrobbler.connection, .connected(username: "gk"))
        scrobbler.played(.fixture(id: 1), startedAt: .now)
        await waitUntil { scrobbler.pendingCount == 0 && scrobbler.status == .idle }
        XCTAssertEqual(scrobbler.pendingCount, 0)
        XCTAssertEqual(scrobbler.status, .idle)
    }

    @MainActor
    func testPlaysAreKeptWhileLastFMIsDown() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scrobbler = makeScrobbler(stub: StubLastFMDown.self, directory: directory)
        scrobbler.played(.fixture(id: 1), startedAt: .now)
        await waitUntil { if case .retrying = scrobbler.status { true } else { false } }
        XCTAssertEqual(scrobbler.pendingCount, 1, "kept for the next try")
        guard case .retrying = scrobbler.status else { return XCTFail("\(scrobbler.status)") }
        scrobbler.disconnect()
        XCTAssertEqual(scrobbler.pendingCount, 0, "disconnecting forgets what was waiting")
    }
}

/// Last.fm taking everything.
private final class StubLastFMAccepts: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { respond(self, #"{"scrobbles": {"@attr": {"accepted": 1, "ignored": 0}}}"#) }
    override func stopLoading() {}
}

/// Last.fm temporarily unavailable (error 16).
private final class StubLastFMDown: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { respond(self, #"{"error": 16, "message": "Temporarily unavailable"}"#) }
    override func stopLoading() {}
}

private func respond(_ stub: URLProtocol, _ body: String) {
    let response = HTTPURLResponse(url: LastFMRequest.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)!
    stub.client?.urlProtocol(stub, didReceive: response, cacheStoragePolicy: .notAllowed)
    stub.client?.urlProtocol(stub, didLoad: Data(body.utf8))
    stub.client?.urlProtocolDidFinishLoading(stub)
}
