import SwiftUI

/// Beat's own volume, with a speaker button to mute and unmute. Disabled on AirPlay, whose volume macOS doesn't
/// let apps set (see `OutputRoute`).
struct VolumeControl: View {
    @Environment(PlaybackQueue.self) private var queue
    @Environment(\.playbackAccent) private var playbackAccent

    var body: some View {
        @Bindable var queue = queue
        HStack(spacing: 4) {
            // Click to mute and unmute. The waves follow the level, like the menu bar's volume icon.
            Button(action: queue.toggleMute) {
                Image(systemName: queue.isMuted ? "speaker.slash.fill" : "speaker.wave.3.fill",
                      variableValue: queue.isMuted ? nil : Double(queue.volume))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .focusable(false)
            .disabled(queue.output.isExternal)
            .help(queue.isMuted ? "Unmute" : "Mute")
            Slider(value: $queue.volume, in: 0...1)
                .tint(playbackAccent)
                .disabled(queue.output.isExternal)
                .help(queue.output.isExternal ? "On AirPlay, set the volume in the AirPlay menu or on the speaker" : "Volume")
                .controlSize(.mini)
                .frame(width: 80)
        }
    }
}
