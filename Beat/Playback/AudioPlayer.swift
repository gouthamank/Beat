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

    init() {
        player.actionAtItemEnd = .advance
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.onTime?(time.seconds) }
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
        if autoplay { play() }
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
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
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
