import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// The system volume, which Beat's volume control shows and sets on iPad and iPhone, so it moves with the volume
/// buttons and Control Centre. (A separate player volume fell out of step with them; Beat's player stays at full.)
/// Read from the audio session; set through the slider of a hidden `MPVolumeView`, the only way an app may change
/// it, which also keeps the system's volume overlay from covering Now Playing.
@MainActor
@Observable
final class SystemVolume {
    static let shared = SystemVolume()

    private(set) var level: Double
    @ObservationIgnored fileprivate weak var slider: UISlider?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private init() {
        let session = AVAudioSession.sharedInstance()
        level = Double(session.outputVolume)
        observation = Self.observe(session)
    }

    func set(_ value: Double) {
        level = value
        slider?.value = Float(value)
    }

    /// Made outside the main actor: the audio session reports changes on its own thread (see the CLAUDE.md gotcha on
    /// callbacks created in `@MainActor` code).
    private nonisolated static func observe(_ session: AVAudioSession) -> NSKeyValueObservation {
        session.observe(\.outputVolume) { session, _ in
            let level = Double(session.outputVolume)
            Task { @MainActor in SystemVolume.shared.level = level }
        }
    }
}

/// The hidden `MPVolumeView` whose slider `SystemVolume` sets. It has to be in the window to work.
private struct SystemVolumeHost: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        view.alpha = 0.01
        view.isUserInteractionEnabled = false
        SystemVolume.shared.slider = view.subviews.lazy.compactMap { $0 as? UISlider }.first
        return view
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {}
}

/// The system volume: a speaker whose waves follow the level, beside a touch slider. No mute button: iPhone and iPad
/// have the ring switch and Control Centre for that.
struct VolumeControl: View {
    @Environment(\.playbackAccent) private var playbackAccent
    private let volume = SystemVolume.shared

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: volume.level == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill",
                  variableValue: volume.level == 0 ? nil : volume.level)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 18, alignment: .leading)
            TouchSlider(value: Binding(get: { volume.level }, set: { volume.set($0) }), in: 0...1)
                .tint(playbackAccent)
                .frame(width: 80)
                .background { SystemVolumeHost().frame(width: 1, height: 1) }
        }
    }
}

/// A touch slider as in Music: a thin line with no knob that thickens under a finger. A tap or drag anywhere on it
/// sets the value. The system slider's knob dwarfed Now Playing's controls, and a tap on its track didn't seek.
struct TouchSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onEditingChanged: (Bool) -> Void = { _ in }
    @State private var dragging = false

    init(value: Binding<Double>, in range: ClosedRange<Double>, onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        _value = value
        self.range = range
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        GeometryReader { geometry in
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? min(max((value - range.lowerBound) / span, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.2))
                Capsule().fill(.tint).frame(width: geometry.size.width * fraction)
            }
            .frame(height: dragging ? 9 : 5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if !dragging {
                        dragging = true
                        onEditingChanged(true)
                    }
                    value = position(drag.location.x, width: geometry.size.width)
                }
                .onEnded { drag in
                    value = position(drag.location.x, width: geometry.size.width)
                    dragging = false
                    onEditingChanged(false)
                })
        }
        .frame(height: 28)
        .animation(.snappy(duration: 0.2), value: dragging)
    }

    private func position(_ x: CGFloat, width: CGFloat) -> Double {
        let fraction = width > 0 ? min(max(x / width, 0), 1) : 0
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }
}
