import Foundation
import MediaPlayer

/// Publishes the current track to Control Center and routes media keys / AirPods controls back.
@MainActor
final class NowPlayingController {
    struct Handlers: Sendable {
        typealias Action = @MainActor @Sendable () -> Void
        var play: Action
        var pause: Action
        var toggle: Action
        var next: Action
        var previous: Action
        var seek: @MainActor @Sendable (TimeInterval) -> Void
    }

    private let artwork: ArtworkCache
    private var artworkTask: Task<Void, Never>?

    init(artwork: ArtworkCache, handlers: Handlers) {
        self.artwork = artwork
        let center = MPRemoteCommandCenter.shared()
        func bind(_ command: MPRemoteCommand, _ action: @escaping Handlers.Action) {
            command.isEnabled = true
            command.addTarget { _ in
                Task { @MainActor in action() }
                return .success
            }
        }
        bind(center.playCommand, handlers.play)
        bind(center.pauseCommand, handlers.pause)
        bind(center.togglePlayPauseCommand, handlers.toggle)
        bind(center.nextTrackCommand, handlers.next)
        bind(center.previousTrackCommand, handlers.previous)
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            let seek = handlers.seek
            Task { @MainActor in seek(position) }
            return .success
        }
    }

    func update(track: Track?, elapsed: TimeInterval, isPlaying: Bool) {
        let info = MPNowPlayingInfoCenter.default()
        guard let track else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }
        var dict = info.nowPlayingInfo ?? [:]
        let trackChanged = (dict[MPMediaItemPropertyPersistentID] as? NSNumber)?.uint64Value != track.id
        if trackChanged { dict = [:] }
        dict[MPMediaItemPropertyPersistentID] = NSNumber(value: track.id)
        dict[MPMediaItemPropertyTitle] = track.title
        dict[MPMediaItemPropertyArtist] = track.displayArtist
        dict[MPMediaItemPropertyAlbumTitle] = track.album
        dict[MPMediaItemPropertyPlaybackDuration] = track.duration
        dict[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        dict[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        dict[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        info.nowPlayingInfo = dict
        info.playbackState = isPlaying ? .playing : .paused

        if trackChanged { loadArtwork(for: track) }
    }

    private func loadArtwork(for track: Track) {
        artworkTask?.cancel()
        artworkTask = Task { [artwork] in
            guard let image = await artwork.image(ArtworkSource(track), size: .large), !Task.isCancelled else { return }
            let item = Self.makeArtwork(image)
            let info = MPNowPlayingInfoCenter.default()
            guard (info.nowPlayingInfo?[MPMediaItemPropertyPersistentID] as? NSNumber)?.uint64Value == track.id else { return }
            info.nowPlayingInfo?[MPMediaItemPropertyArtwork] = item
        }
    }

    /// MediaPlayer calls the request handler on a background queue, so it must not be main-actor isolated.
    private nonisolated static func makeArtwork(_ image: PlatformImage) -> MPMediaItemArtwork {
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
