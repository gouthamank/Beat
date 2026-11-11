import CryptoKit
import Foundation

enum LastFMSettings {
    /// Off by default: with it off, Beat makes no requests to Last.fm and queues nothing.
    static let enabledKey = "lastfm.enabled"
    /// The connected account's name, for Settings. Not a secret; the session key is (Keychain).
    static let usernameKey = "lastfm.username"
    static let sessionAccount = "lastfm-session"
}

/// Beat's Last.fm API account, compiled in from the git-ignored `Config/Secrets.xcconfig` (see README).
/// They identify the app, not the user: the user's own access is the session key from `auth.getSession`.
struct LastFMCredentials: Equatable, Sendable {
    let apiKey: String
    let secret: String

    /// Nil when this build has no key, which is also the feature switch: without one, Settings hides
    /// Last.fm and the scrobbler does nothing. The example file's placeholders count as no key.
    static var bundled: LastFMCredentials? {
        let info = Bundle.main.infoDictionary
        return make(apiKey: info?["LastFMAPIKey"] as? String, secret: info?["LastFMSharedSecret"] as? String)
    }

    static func make(apiKey: String?, secret: String?) -> LastFMCredentials? {
        guard let apiKey, let secret, !apiKey.isEmpty, !secret.isEmpty,
              apiKey != "your_api_key", secret != "your_shared_secret" else { return nil }
        return LastFMCredentials(apiKey: apiKey, secret: secret)
    }
}

/// A signed call to Last.fm's API, sent as a form POST.
struct LastFMRequest: Equatable, Sendable {
    static let endpoint = URL(string: "https://ws.audioscrobbler.com/2.0/")!

    let parameters: [String: String]

    init(method: String, parameters: [String: String] = [:], credentials: LastFMCredentials, sessionKey: String? = nil) {
        var all = parameters
        all["method"] = method
        all["api_key"] = credentials.apiKey
        if let sessionKey { all["sk"] = sessionKey }
        all["api_sig"] = Self.signature(all, secret: credentials.secret)
        all["format"] = "json"
        self.parameters = all
    }

    /// MD5 of every parameter as name then value, in byte order of name, followed by the secret.
    /// `format` and `callback` aren't signed.
    static func signature(_ parameters: [String: String], secret: String) -> String {
        let text = parameters
            .filter { $0.key != "format" && $0.key != "callback" }
            .sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
            .map { $0.key + $0.value }
            .joined() + secret
        return Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    var urlRequest: URLRequest {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Beat/1.0 (macOS music player)", forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(Self.formBody(parameters).utf8)
        return request
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func formBody(_ parameters: [String: String]) -> String {
        func encode(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "" }
        return parameters
            .sorted { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }
            .map { "\(encode($0.key))=\(encode($0.value))" }
            .joined(separator: "&")
    }

    // MARK: Calls

    static func getToken(_ credentials: LastFMCredentials) -> LastFMRequest {
        LastFMRequest(method: "auth.getToken", credentials: credentials)
    }

    static func getSession(token: String, _ credentials: LastFMCredentials) -> LastFMRequest {
        LastFMRequest(method: "auth.getSession", parameters: ["token": token], credentials: credentials)
    }

    static func nowPlaying(_ scrobble: Scrobble, sessionKey: String, _ credentials: LastFMCredentials) -> LastFMRequest {
        LastFMRequest(method: "track.updateNowPlaying", parameters: scrobble.fields(index: nil),
                      credentials: credentials, sessionKey: sessionKey)
    }

    static func scrobble(_ batch: [Scrobble], sessionKey: String, _ credentials: LastFMCredentials) -> LastFMRequest {
        var fields: [String: String] = [:]
        for (i, scrobble) in batch.prefix(ScrobbleQueue.batchSize).enumerated() {
            fields.merge(scrobble.fields(index: i)) { _, new in new }
        }
        return LastFMRequest(method: "track.scrobble", parameters: fields, credentials: credentials, sessionKey: sessionKey)
    }

    /// The page where the user approves Beat, for a token from `auth.getToken`.
    static func approvalURL(token: String, apiKey: String) -> URL? {
        var components = URLComponents(string: "https://www.last.fm/api/auth/")
        components?.queryItems = [URLQueryItem(name: "api_key", value: apiKey), URLQueryItem(name: "token", value: token)]
        return components?.url
    }

    // MARK: Answers

    struct Token: Decodable, Sendable { let token: String }
    struct Session: Decodable, Sendable { let name: String; let key: String }
    struct SessionAnswer: Decodable, Sendable { let session: Session }
    /// Scrobbles and now-playing updates: anything without an error counts as taken.
    struct Accepted: Decodable, Sendable {}

    private struct APIError: Decodable { let error: Int; let message: String? }

    /// Not yet approved in the browser (`auth.getSession` while the user hasn't clicked Allow).
    static let unauthorizedToken = 14

    static func result<Value: Decodable & Sendable>(_ type: Value.Type, data: Data, response: URLResponse?) -> LastFMResult<Value> {
        if let error = try? JSONDecoder().decode(APIError.self, from: data) {
            let message = error.message ?? "Last.fm error \(error.error)."
            switch error.error {
            case 9: return .badSession(message)
            case 11, 16, 29: return .retryLater(message)
            default: return .failed(code: error.error, message: message)
            }
        }
        if let status = (response as? HTTPURLResponse)?.statusCode, status >= 500 {
            return .retryLater("Last.fm is having trouble (\(status)).")
        }
        guard let value = try? JSONDecoder().decode(Value.self, from: data) else {
            return .failed(code: 0, message: "Last.fm sent an answer Beat didn't understand.")
        }
        return .success(value)
    }
}

enum LastFMResult<Value: Sendable>: Sendable {
    case success(Value)
    /// Offline, or Last.fm busy or down: worth trying again later.
    case retryLater(String)
    /// The session key was revoked or expired: the user has to connect again.
    case badSession(String)
    case failed(code: Int, message: String)
}

/// Sends requests. The session is injectable for tests.
actor LastFMClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send<Value: Decodable & Sendable>(_ request: LastFMRequest, as type: Value.Type) async -> LastFMResult<Value> {
        guard let (data, response) = try? await session.data(for: request.urlRequest) else {
            return .retryLater("Couldn't reach Last.fm.")
        }
        return LastFMRequest.result(type, data: data, response: response)
    }
}
