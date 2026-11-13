import AVFoundation

/// Thin wrapper over AVQueuePlayer holding the current item plus one preloaded upcoming item,
/// so track transitions don't wait on file loading.
@MainActor
final class AudioPlayer {
    var onTime: ((TimeInterval) -> Void)?
    /// The current item finished and the preloaded upcoming item started.
    var onAdvanced: (() -> Void)?
    /// The current item finished (or failed) with nothing queued after it.
    var onFinished: (() -> Void)?

    var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }

    private let player = AVQueuePlayer()

    /// The one long-lived player, for the system output picker to route.
    var outputPlayer: AVPlayer { player }

    /// What's playing, as samples, for the visualizer.
    let samples = SampleBuffer()
    private var current: AVPlayerItem?
    private var upcoming: AVPlayerItem?
    /// Each item's tap attachment. Setting an audio mix on an item that's already playing rebuilds its
    /// render chain and can click, so playback waits for the current item's tap.
    private var currentTap: Task<Void, Never>?
    private var upcomingTap: Task<Void, Never>?
    /// A play() waiting on `currentTap`; pause, stop and load cancel it.
    private var pendingPlay: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var timeObserver: Any?
    /// Seeks still on their way. Meanwhile the periodic observer keeps reporting the old position, and passing it
    /// on made the progress bar jump back and forth between the old and new points after a tap to seek.
    private var pendingSeeks = 0

    init() {
        player.actionAtItemEnd = .advance
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.pendingSeeks == 0 else { return }
                self.onTime?(time.seconds)
            }
        }
        for name in [AVPlayerItem.didPlayToEndTimeNotification, AVPlayerItem.failedToPlayToEndTimeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let item = note.object as? AVPlayerItem
                MainActor.assumeIsolated { self?.itemEnded(item) }
            })
        }
    }

    func load(_ url: URL, upcoming upcomingURL: URL?, autoplay: Bool) {
        cancelPendingPlay()
        player.removeAllItems()
        let item = AVPlayerItem(url: url)
        currentTap = attachTap(item)
        current = item
        upcoming = nil
        player.insert(item, after: nil)
        setUpcoming(upcomingURL)
        // Without autoplay, paused: the queue player keeps its rate across items, so loading while playing
        // (Next on the last song) carried on playing while the queue showed it stopped.
        if autoplay { play() } else { player.pause() }
    }

    func setUpcoming(_ url: URL?) {
        if let upcoming { player.remove(upcoming) }
        upcoming = nil
        upcomingTap = nil
        guard let url, let current else { return }
        let item = AVPlayerItem(url: url)
        upcomingTap = attachTap(item)
        upcoming = item
        player.insert(item, after: current)
    }

    /// Feeds the visualizer. Off in Settings, items play through exactly as before, with no tap.
    private func attachTap(_ item: AVPlayerItem) -> Task<Void, Never>? {
        guard UserDefaults.standard.object(forKey: "visualizer.enabled") as? Bool ?? true else { return nil }
        let samples = samples
        return Task { await AudioTap.attach(to: item, buffer: samples) }
    }

    func play() {
        cancelPendingPlay()
        guard let tap = currentTap else { return player.play() }
        pendingPlay = Task { [weak self] in
            await tap.value
            guard !Task.isCancelled else { return }
            self?.player.play()
        }
    }

    func pause() {
        cancelPendingPlay()
        player.pause()
    }

    private func cancelPendingPlay() {
        pendingPlay?.cancel()
        pendingPlay = nil
    }

    func seek(to seconds: TimeInterval) {
        pendingSeeks += 1
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero,
                    completionHandler: Self.seekCompletion(for: self))
    }

    /// Made outside the main actor: AVFoundation calls it on its own queue (see the CLAUDE.md gotcha on callbacks
    /// created in `@MainActor` code). A seek replaced by a newer one finishes too, unfinished, so each one counts down.
    private nonisolated static func seekCompletion(for player: AudioPlayer) -> @Sendable (Bool) -> Void {
        { [weak player] _ in
            Task { @MainActor in
                guard let player else { return }
                player.pendingSeeks = max(player.pendingSeeks - 1, 0)
            }
        }
    }

    func stop() {
        cancelPendingPlay()
        player.pause()
        player.removeAllItems()
        current = nil
        upcoming = nil
        currentTap = nil
        upcomingTap = nil
    }

    private func itemEnded(_ item: AVPlayerItem?) {
        guard let item, item === current else { return }
        if let upcoming {
            current = upcoming
            currentTap = upcomingTap
            self.upcoming = nil
            upcomingTap = nil
            onAdvanced?()
        } else {
            current = nil
            onFinished?()
        }
    }
}
