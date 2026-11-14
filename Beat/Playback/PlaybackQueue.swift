import AVFoundation
import Observation

/// Beat's player: owns the queue, drives AudioPlayer, records history and updates Now Playing.
@MainActor
@Observable
final class PlaybackQueue {
    private(set) var state = QueueState()
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    /// Counts presses of Next on the last song. Full Now Playing closes on it; the track stays in the bar.
    private(set) var skippedPastEnd = 0
    var volume: Float {
        didSet {
            player.volume = volume
            defaults.set(volume, forKey: "volume")
            if !togglingMute { mute.changedManually() }
        }
    }
    var isMuted: Bool { volume == 0 }

    var current: Track? { state.current }
    /// For the output (AirPlay) picker, which routes Beat's player without changing the system output.
    var outputPlayer: AVPlayer { player.outputPlayer }
    /// Samples of what's playing, for the visualizer.
    var samples: SampleBuffer { player.samples }
    var isShuffled: Bool { state.isShuffled }
    var repeatMode: RepeatMode { state.repeatMode }

    @ObservationIgnored private let player: any AudioPlaying
    /// Where the volume is remembered; tests pass their own, so they never change Beat's.
    @ObservationIgnored private let defaults: UserDefaults
    /// The output (AirPlay) picker, shared by every now-playing bar so the route survives navigation. Made when a
    /// bar first shows it, so a queue in tests never attaches one (a second picker drops the route).
    @ObservationIgnored private(set) lazy var output = OutputRoute(player: player.outputPlayer)
    @ObservationIgnored private let history: PlayHistoryStore
    /// Nil in tests, which leave the system's Now Playing and media keys alone.
    @ObservationIgnored private var nowPlaying: NowPlayingController?
    @ObservationIgnored private var mute = VolumeMute()
    @ObservationIgnored private var togglingMute = false
    /// Whether the current item has already been counted as a play.
    @ObservationIgnored private var countedCurrent = false
    @ObservationIgnored private let scrobbler: Scrobbler?
    /// Whether Last.fm has been told the current item is playing.
    @ObservationIgnored private var announcedCurrent = false

    /// Tests pass a stand-in player and their own defaults, and turn off `publishesNowPlaying`.
    init(history: PlayHistoryStore, artwork: ArtworkCache, scrobbler: Scrobbler? = nil,
         player: any AudioPlaying = AudioPlayer(), defaults: UserDefaults = .standard, publishesNowPlaying: Bool = true) {
        self.player = player
        self.defaults = defaults
        self.history = history
        self.scrobbler = scrobbler
        #if os(macOS)
        self.volume = defaults.object(forKey: "volume") as? Float ?? 0.8
        #else
        // Full: on iPad and iPhone Beat's volume control is the system volume (SystemVolume).
        self.volume = 1
        #endif
        player.volume = volume
        player.onTime = { [weak self] in self?.timeChanged($0) }
        player.onAdvanced = { [weak self] in self?.advancedAutomatically() }
        player.onFinished = { [weak self] in self?.finished() }
        guard publishesNowPlaying else { return }
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

    /// The speaker button: mutes, or goes back to the volume from before muting.
    func toggleMute() {
        togglingMute = true
        volume = mute.toggled(current: volume)
        togglingMute = false
    }

    func play() {
        guard state.current != nil else { return }
        player.play()
        isPlaying = true
        publishNowPlaying()
        announce()
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
            // As when the last song ends by itself: it stays loaded, paused at the start. Stopping cleared the
            // queue, and Now Playing and the bar vanished under the click.
            rewindAtEnd()
            skippedPastEnd += 1
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
        announcedCurrent = false
        currentTime = 0
        publishNowPlaying()
        announce()
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
        announcedCurrent = false
        currentTime = 0
        refreshUpcoming()
        publishNowPlaying()
        announce()
    }

    private func finished() { rewindAtEnd() }

    /// The queue has run out: the last track stays, paused at its start.
    private func rewindAtEnd() {
        isPlaying = false
        currentTime = 0
        // Playing it again from the start is a new play.
        countedCurrent = false
        announcedCurrent = false
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
            scrobbler?.played(track, startedAt: .now - seconds)
        }
    }

    /// Tells Last.fm once per track, when it actually starts playing (not when loaded paused).
    private func announce() {
        guard isPlaying, !announcedCurrent, let track = state.current else { return }
        announcedCurrent = true
        scrobbler?.nowPlaying(track)
    }

    private func publishNowPlaying() {
        nowPlaying?.update(track: state.current, elapsed: currentTime, isPlaying: isPlaying)
    }

    /// Skips songs whose file has gone (moved or deleted since Music last saw it). Only files can go missing that
    /// way: synced songs on iPad and iPhone are `ipod-library://` addresses, which the file check rejected, so
    /// nothing played.
    private static func isPlayable(_ track: Track) -> Bool {
        guard track.location.isFileURL else { return true }
        return FileManager.default.fileExists(atPath: track.location.path)
    }
}

/// Mute that remembers the level to come back to.
struct VolumeMute: Equatable, Sendable {
    /// Unmuting from silence that wasn't a mute (the slider dragged to zero) comes back to this.
    static let fallback: Float = 0.5

    /// The level before muting; nil when there's nothing to go back to.
    private(set) var saved: Float?

    /// The volume after the speaker button: silence (remembering `current`), or the remembered level.
    mutating func toggled(current: Float) -> Float {
        if current > 0 {
            saved = current
            return 0
        }
        defer { saved = nil }
        return saved ?? Self.fallback
    }

    /// The volume was set some other way (slider, ⌘↑/↓), so a later unmute shouldn't jump back to an old level.
    mutating func changedManually() { saved = nil }
}
