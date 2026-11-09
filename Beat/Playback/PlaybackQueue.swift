import AVFoundation
import Observation

/// Beat's player: owns the queue, drives AudioPlayer, records history and updates Now Playing.
@MainActor
@Observable
final class PlaybackQueue {
    private(set) var state = QueueState()
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    var volume: Float {
        didSet {
            player.volume = volume
            UserDefaults.standard.set(volume, forKey: "volume")
        }
    }

    var current: Track? { state.current }
    /// For the output (AirPlay) picker, which routes Beat's player without changing the system output.
    var outputPlayer: AVPlayer { player.outputPlayer }
    /// Samples of what's playing, for the visualizer.
    var samples: SampleBuffer { player.samples }
    var isShuffled: Bool { state.isShuffled }
    var repeatMode: RepeatMode { state.repeatMode }

    @ObservationIgnored private let player: AudioPlayer
    /// The output (AirPlay) picker, shared by every now-playing bar so the route survives navigation.
    @ObservationIgnored let output: OutputRoute
    @ObservationIgnored private let history: PlayHistoryStore
    @ObservationIgnored private var nowPlaying: NowPlayingController!
    /// Whether the current item has already been counted as a play.
    @ObservationIgnored private var countedCurrent = false

    init(history: PlayHistoryStore, artwork: ArtworkCache) {
        let player = AudioPlayer()
        self.player = player
        output = OutputRoute(player: player.outputPlayer)
        self.history = history
        self.volume = UserDefaults.standard.object(forKey: "volume") as? Float ?? 0.8
        player.volume = volume
        player.onTime = { [weak self] in self?.timeChanged($0) }
        player.onAdvanced = { [weak self] in self?.advancedAutomatically() }
        player.onFinished = { [weak self] in self?.finished() }
        nowPlaying = NowPlayingController(artwork: artwork, handlers: .init(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in self?.togglePlayPause() },
            next: { [weak self] in self?.next() },
            previous: { [weak self] in self?.previous() },
            seek: { [weak self] in self?.seek(to: $0) }
        ))
    }

    // MARK: Starting playback

    func play(_ tracks: [Track], startAt start: Int = 0, shuffled: Bool = false) {
        guard !tracks.isEmpty else { return }
        state.load(tracks, startAt: start, shuffled: shuffled)
        if let current = state.current, !Self.isPlayable(current) {
            guard let i = state.index(after: state.index!, manual: true, isPlayable: Self.isPlayable) else { return }
            state.move(to: i)
        }
        startCurrent(autoplay: true)
    }

    func playNext(_ tracks: [Track]) {
        let wasEmpty = state.current == nil
        state.insertNext(tracks)
        wasEmpty ? startCurrent(autoplay: true) : refreshUpcoming()
    }

    func addToQueue(_ tracks: [Track]) {
        let wasEmpty = state.current == nil
        state.append(tracks)
        wasEmpty ? startCurrent(autoplay: true) : refreshUpcoming()
    }

    func jump(to index: Int) {
        state.move(to: index)
        startCurrent(autoplay: true)
    }

    func remove(at index: Int) {
        state.remove(at: index)
        refreshUpcoming()
    }

    func moveUpNext(fromOffsets source: IndexSet, toOffset destination: Int) {
        state.moveUpNext(fromOffsets: source, toOffset: destination)
        refreshUpcoming()
    }

    func clearUpNext() {
        state.clearUpNext()
        refreshUpcoming()
    }

    /// Removes only the songs added with Play Next or Add to Queue.
    func clearQueued() {
        state.clearQueued()
        refreshUpcoming()
    }

    // MARK: Transport

    func togglePlayPause() { isPlaying ? pause() : play() }

    func play() {
        guard state.current != nil else { return }
        player.play()
        isPlaying = true
        publishNowPlaying()
    }

    func pause() {
        player.pause()
        isPlaying = false
        publishNowPlaying()
    }

    func next() {
        guard let i = state.index else { return }
        if let track = state.current, !countedCurrent, (2..<20).contains(currentTime) {
            history.recordSkip(track.id)
        }
        guard let j = state.index(after: i, manual: true, isPlayable: Self.isPlayable) else {
            stop()
            return
        }
        state.move(to: j)
        startCurrent(autoplay: isPlaying)
    }

    /// Restarts the current track after 3 seconds of play; otherwise goes back one track.
    func previous() {
        guard let i = state.index else { return }
        if currentTime > 3 { seek(to: 0); return }
        guard let j = state.index(before: i, isPlayable: Self.isPlayable) else { seek(to: 0); return }
        state.move(to: j)
        startCurrent(autoplay: isPlaying)
    }

    func seek(to seconds: TimeInterval) {
        player.seek(to: seconds)
        currentTime = seconds
        publishNowPlaying()
    }

    func toggleShuffle() {
        state.setShuffle(!state.isShuffled)
        refreshUpcoming()
    }

    func cycleRepeat() {
        state.repeatMode = state.repeatMode.next
        refreshUpcoming()
    }

    func stop() {
        player.stop()
        state.clear()
        isPlaying = false
        currentTime = 0
        publishNowPlaying()
    }

    // MARK: Internals

    private func startCurrent(autoplay: Bool) {
        guard let track = state.current else { return stop() }
        player.load(track.location, upcoming: upcomingURL(), autoplay: autoplay)
        isPlaying = autoplay
        countedCurrent = false
        currentTime = 0
        publishNowPlaying()
    }

    private func upcomingURL() -> URL? {
        guard let i = state.index, let j = state.index(after: i, manual: false, isPlayable: Self.isPlayable) else { return nil }
        return state.items[j].location
    }

    private func refreshUpcoming() {
        guard state.current != nil else { return }
        player.setUpcoming(upcomingURL())
    }

    private func advancedAutomatically() {
        guard let i = state.index, let j = state.index(after: i, manual: false, isPlayable: Self.isPlayable) else { return }
        state.move(to: j)
        countedCurrent = false
        currentTime = 0
        refreshUpcoming()
        publishNowPlaying()
    }

    private func finished() {
        isPlaying = false
        currentTime = 0
        // Leave the last track loaded at the start, like Music does.
        if let track = state.current { player.load(track.location, upcoming: nil, autoplay: false) }
        publishNowPlaying()
    }

    private func timeChanged(_ seconds: TimeInterval) {
        guard seconds.isFinite else { return }
        currentTime = seconds
        guard !countedCurrent, let track = state.current, track.duration > 0 else { return }
        if seconds >= min(track.duration * 0.5, 240) {
            countedCurrent = true
            history.recordPlay(track.id)
        }
    }

    private func publishNowPlaying() {
        nowPlaying.update(track: state.current, elapsed: currentTime, isPlaying: isPlaying)
    }

    private static func isPlayable(_ track: Track) -> Bool {
        FileManager.default.fileExists(atPath: track.location.path)
    }
}
