import AppKit
import Observation

/// Scrobbles to Last.fm: now-playing updates as songs start, and every play Beat counts (half the song or
/// 4 minutes, the same rule as Last.fm's) through a queue saved on disk, sent in batches and retried
/// while offline. Off by default; with it off nothing is sent or queued.
@MainActor
@Observable
final class Scrobbler {
    enum Connection: Equatable {
        case disconnected
        case waitingForApproval
        case connected(username: String)
    }

    enum Status: Equatable {
        case idle
        case sending
        /// Offline or Last.fm trouble; the queue is kept and sent again later.
        case retrying(String)
        /// Last.fm no longer accepts the session. Plays keep queueing until the user connects again.
        case needsReconnect
        case failed(String)
    }

    /// Where the session key lives: the Keychain, or memory in tests.
    struct SessionStorage {
        var load: () -> String?
        var save: (String?) -> Void

        static var keychain: SessionStorage {
            SessionStorage(load: { Keychain.string(for: LastFMSettings.sessionAccount) },
                           save: { Keychain.set($0, for: LastFMSettings.sessionAccount) })
        }
    }

    /// Nil when this build has no API key: scrobbling is then off entirely and Settings has no Last.fm tab.
    let credentials: LastFMCredentials?
    private(set) var connection: Connection
    private(set) var status: Status = .idle
    private(set) var pendingCount: Int

    @ObservationIgnored private var queue: ScrobbleQueue
    @ObservationIgnored private var sessionKey: String?
    @ObservationIgnored private let storage: SessionStorage
    @ObservationIgnored private let client: LastFMClient
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var flushing = false
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var retryDelay: Duration = Scrobbler.firstRetry
    @ObservationIgnored private var connectTask: Task<Void, Never>?

    private static let firstRetry: Duration = .seconds(60)
    private static let longestRetry: Duration = .seconds(30 * 60)

    init(credentials: LastFMCredentials? = .bundled, fileURL: URL? = Scrobbler.defaultURL,
         session: URLSession = .shared, defaults: UserDefaults = .standard, storage: SessionStorage = .keychain) {
        self.credentials = credentials
        self.fileURL = fileURL
        self.defaults = defaults
        self.storage = storage
        client = LastFMClient(session: session)
        queue = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(ScrobbleQueue.self, from: $0) }
            ?? ScrobbleQueue()
        pendingCount = queue.pending.count
        sessionKey = storage.load()
        let username = defaults.string(forKey: LastFMSettings.usernameKey)
        if let username, sessionKey != nil {
            connection = .connected(username: username)
        } else {
            connection = .disconnected
            // Connected once, but the session has gone since: say so rather than looking signed out.
            if username != nil { status = .needsReconnect }
        }
        flush()
    }

    private var isEnabled: Bool { defaults.bool(forKey: LastFMSettings.enabledKey) }
    /// Connected now, or connected before and waiting to reconnect: plays are kept either way.
    private var hasAccount: Bool { defaults.string(forKey: LastFMSettings.usernameKey) != nil }

    // MARK: Playback

    func nowPlaying(_ track: Track) {
        guard isEnabled, let credentials, let sessionKey, let scrobble = Scrobble(track, startedAt: .now) else { return }
        let request = LastFMRequest.nowPlaying(scrobble, sessionKey: sessionKey, credentials)
        Task { [client] in _ = await client.send(request, as: LastFMRequest.Accepted.self) }
    }

    func played(_ track: Track, startedAt: Date) {
        guard isEnabled, credentials != nil, hasAccount, let scrobble = Scrobble(track, startedAt: startedAt) else { return }
        queue.enqueue(scrobble)
        changed()
        flush()
    }

    /// Sends what's waiting, a batch at a time, until the queue is empty or a request fails.
    func flush() {
        guard !flushing, isEnabled, let credentials, let sessionKey else { return }
        retryTask?.cancel()
        retryTask = nil
        queue.dropExpired(now: .now)
        changed()
        flushing = true
        Task {
            await send(credentials: credentials, sessionKey: sessionKey)
            flushing = false
        }
    }

    private func send(credentials: LastFMCredentials, sessionKey: String) async {
        while true {
            let batch = queue.nextBatch
            guard !batch.isEmpty else {
                status = .idle
                retryDelay = Self.firstRetry
                return
            }
            status = .sending
            switch await client.send(.scrobble(batch, sessionKey: sessionKey, credentials), as: LastFMRequest.Accepted.self) {
            case .success:
                queue.remove(batch)
                changed()
            case .retryLater(let message), .failed(_, let message):
                status = .retrying(message)
                scheduleRetry()
                return
            case .badSession:
                sessionLost()
                return
            }
        }
    }

    private func scheduleRetry() {
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, Self.longestRetry)
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    // MARK: Account

    /// Asks Last.fm for a token, opens its approval page in the browser, and waits (up to 5 minutes) for
    /// the user to allow Beat.
    func connect() {
        guard let credentials, connectTask == nil else { return }
        connection = .waitingForApproval
        status = .idle
        connectTask = Task {
            // A cancelled attempt leaves `connectTask` alone: it may already hold a newer one.
            defer { if !Task.isCancelled { connectTask = nil } }
            guard case .success(let answer) = await client.send(.getToken(credentials), as: LastFMRequest.Token.self),
                  let url = LastFMRequest.approvalURL(token: answer.token, apiKey: credentials.apiKey) else {
                connection = .disconnected
                status = .failed("Couldn't start signing in to Last.fm.")
                return
            }
            NSWorkspace.shared.open(url)
            for _ in 0..<100 {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                switch await client.send(.getSession(token: answer.token, credentials), as: LastFMRequest.SessionAnswer.self) {
                case .success(let answer):
                    signedIn(answer.session)
                    return
                case .failed(code: LastFMRequest.unauthorizedToken, message: _), .retryLater:
                    continue
                case .failed(_, let message):
                    connection = .disconnected
                    status = .failed(message)
                    return
                case .badSession:
                    connection = .disconnected
                    status = .failed("Last.fm didn't accept the sign-in. Try Connect again.")
                    return
                }
            }
            connection = .disconnected
            status = .failed("Signing in to Last.fm timed out. Try Connect again.")
        }
    }

    func cancelConnect() {
        connectTask?.cancel()
        connectTask = nil
        if connection == .waitingForApproval { connection = .disconnected }
    }

    /// Forgets the account, and the plays still waiting: they'd otherwise go to whichever account
    /// connects next.
    func disconnect() {
        cancelConnect()
        retryTask?.cancel()
        retryTask = nil
        sessionKey = nil
        storage.save(nil)
        defaults.removeObject(forKey: LastFMSettings.usernameKey)
        queue = ScrobbleQueue()
        changed()
        connection = .disconnected
        status = .idle
    }

    private func signedIn(_ session: LastFMRequest.Session) {
        sessionKey = session.key
        storage.save(session.key)
        defaults.set(session.name, forKey: LastFMSettings.usernameKey)
        connection = .connected(username: session.name)
        status = .idle
        retryDelay = Self.firstRetry
        flush()
    }

    private func sessionLost() {
        sessionKey = nil
        storage.save(nil)
        connection = .disconnected
        status = .needsReconnect
    }

    // MARK: Saving

    private func changed() {
        pendingCount = queue.pending.count
        guard let fileURL, let data = try? JSONEncoder().encode(queue) else { return }
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    nonisolated static var defaultURL: URL? {
        PageStore.defaultDirectory?.appendingPathComponent("scrobbles.json")
    }
}
