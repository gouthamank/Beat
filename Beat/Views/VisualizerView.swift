import SwiftUI

enum VisualizerStyle: String, CaseIterable {
    case horizon, terrain, rings, starfield, fountain, constellation, bars, waveform

    var title: String { self == .rings ? "Spectrum Rings" : rawValue.capitalized }

    /// Draws a whole scene on its own dark ground (`VisualizerScenes`), rather than over the cover's backdrop.
    var isScene: Bool { self != .waveform }
}

/// Reads the tap's samples each frame, analyses and smooths them. Plain class rather than observable:
/// the timeline drives it, and nothing else needs to watch it.
@MainActor
final class VisualizerEngine {
    private let analyzer = SpectrumAnalyzer()
    private var bands = Smoother(count: SpectrumAnalyzer.bandCount)
    private var scalars = Smoother(count: 2)
    private var waveform = [Float](repeating: 0, count: SpectrumAnalyzer.waveformPoints)

    /// Everything has eased back to zero after pausing, so the timeline can stop.
    private(set) var isAtRest = true

    func next(samples: SampleBuffer, playing: Bool) -> SpectrumFrame {
        let target: SpectrumFrame
        if playing {
            let (latest, rate) = samples.latest()
            target = analyzer.analyze(latest, sampleRate: rate)
        } else {
            target = .silent
        }
        let smoothedBands = bands.update(target.bands)
        let smoothedScalars = scalars.update([target.level, target.bass])
        for i in waveform.indices where i < target.waveform.count {
            waveform[i] += (target.waveform[i] - waveform[i]) * 0.5
        }
        isAtRest = !playing && smoothedBands.allSatisfy { $0 < 0.01 } && smoothedScalars.allSatisfy { $0 < 0.01 }
        return SpectrumFrame(bands: smoothedBands, level: smoothedScalars[0], bass: smoothedScalars[1], waveform: waveform)
    }

    private var bounce = CoverBounce()
    private var lastDate: Date?

    /// The cover's scale this frame, for Radial around Now Playing's cover: it springs out on each kick.
    func coverScale(_ frame: SpectrumFrame, at date: Date) -> CGFloat {
        let dt = lastDate.map { min(max(date.timeIntervalSince($0), 0), 0.05) } ?? 1 / 60
        lastDate = date
        return CGFloat(bounce.update(bass: frame.bass, dt: dt))
    }
}

/// A cover that thumps with the music: a rise in the bass kicks it outward, and a loose spring pulls it back
/// with a little overshoot, so each kick lands with some weight instead of the cover just tracking the level.
struct CoverBounce {
    private(set) var scale = 1.0
    private var velocity = 0.0
    private var lastBass: Float = 0

    // Tuned by ear in a toy with knobs, on real tracks.
    /// Spring strength and damping: a loose spring, about 2.7 swings a second, settling within a second.
    private static let stiffness = 281.0, damping = 7.2
    /// How hard a rise in the bass kicks the cover, and how much it swells with the level of the bass.
    private static let kick = 3.24, swell = 0.064
    private static let range = 0.88...1.23

    mutating func update(bass: Float, dt: Double) -> Double {
        let rise = Double(max(0, bass - lastBass))
        lastBass = bass
        velocity += rise * Self.kick
        let target = 1 + Double(bass) * Self.swell
        velocity += (Self.stiffness * (target - scale) - Self.damping * velocity) * dt
        scale = (scale + velocity * dt).clamped(to: Self.range)
        return scale
    }
}

/// The visualization itself, in one of its styles, coloured from the cover.
struct VisualizerView: View {
    let palette: ArtworkPalette?
    let style: VisualizerStyle
    @Environment(PlaybackQueue.self) private var queue
    @State private var engine = VisualizerEngine()
    @State private var scenes = VisualizerScenes()

    private var primary: Color { palette?.primary.color ?? .accentColor }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !queue.isPlaying && engine.isAtRest)) { timeline in
            let frame = engine.next(samples: queue.samples, playing: queue.isPlaying)
            GeometryReader { proxy in
                let _ = scenes.step(frame, style: style, date: timeline.date, size: proxy.size)
                let colours = SceneColours(palette: palette)
                Canvas { context, size in
                    if style == .waveform {
                        drawWaveform(frame, &context, size)
                    } else {
                        scenes.draw(frame, style: style, colours: colours, in: &context, size: size)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    /// A glowing oscilloscope line across the middle.
    private func drawWaveform(_ frame: SpectrumFrame, _ context: inout GraphicsContext, _ size: CGSize) {
        let points = frame.waveform
        guard points.count > 1 else { return }
        let midY = size.height / 2
        let amplitude = size.height * 0.3
        var path = Path()
        for (i, value) in points.enumerated() {
            let x = size.width * CGFloat(i) / CGFloat(points.count - 1)
            let y = midY - CGFloat(max(-1, min(1, value * 1.4))) * amplitude
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        let width = 2 + CGFloat(frame.level) * 3
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: 10))
            glow.stroke(path, with: .color(primary.opacity(0.7)), style: StrokeStyle(lineWidth: width * 3, lineCap: .round, lineJoin: .round))
        }
        context.stroke(path, with: .color(primary), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}

/// Spectrum bars radiating in a ring, mirrored left and right, around Now Playing's cover (Radial).
enum RadialBars {
    /// How much of a bar shows, by the direction it points: all of it to the sides and above, falling off steeply
    /// below and none straight down, where Now Playing's title and artist sit under the cover.
    static func visibility(pointing direction: CGPoint) -> Double {
        pow(1 - max(0, Double(direction.y)), 2.5)
    }

    /// Bar thickness and the space between neighbours at the cover's edge, in points.
    static let width: CGFloat = 5.9, gap: CGFloat = 4.1

    /// As many bars as fit around the inner circle at `width + gap` each, so they're spaced the same at any
    /// cover size. Each takes its value from the spectrum, mirrored (bass at the top, highs at the bottom).
    static func draw(_ frame: SpectrumFrame, in context: inout GraphicsContext, centre: CGPoint, inner: CGFloat, reach: CGFloat,
                     colour: Color) {
        let bands = frame.bands
        guard bands.count > 1 else { return }
        let count = max(8, Int((2 * .pi * inner / (width + gap)).rounded()))
        for k in 0..<count {
            let around = Double(k) / Double(count)
            // 0 at the top, 1 at the bottom, either way round; between two bands, a blend of both.
            let position = (around < 0.5 ? around * 2 : (1 - around) * 2) * Double(bands.count - 1)
            let low = Int(position), blend = Float(position - Double(low))
            let value = bands[low] * (1 - blend) + bands[min(bands.count - 1, low + 1)] * blend
            let angle = around * 2 * .pi - .pi / 2
            let length = 6 + CGFloat(value) * reach
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            var line = Path()
            line.move(to: CGPoint(x: centre.x + direction.x * inner, y: centre.y + direction.y * inner))
            line.addLine(to: CGPoint(x: centre.x + direction.x * (inner + length), y: centre.y + direction.y * (inner + length)))
            let opacity = (0.4 + 0.6 * Double(value)) * visibility(pointing: direction)
            guard opacity > 0.01 else { continue }
            context.stroke(line, with: .color(colour.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }
}

/// Now Playing's cover with Radial around it when `active`: the bars radiate from behind it and the cover
/// thumps on the kick. The bars are a background, so turning them on doesn't move anything.
struct RadialCover<Cover: View>: View {
    let active: Bool
    let colour: Color
    @ViewBuilder let cover: Cover
    @Environment(PlaybackQueue.self) private var queue
    @State private var engine = VisualizerEngine()

    /// Room around the cover for the bars, which start 5 pt from its edge and reach up to 34% of its shorter side.
    private static var margin: CGFloat { 220 }

    var body: some View {
        // One structure either way, so the cover keeps its identity (and its loaded image) when toggled.
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !active || (!queue.isPlaying && engine.isAtRest))) { timeline in
            let frame = engine.next(samples: queue.samples, playing: active && queue.isPlaying)
            cover
                .scaleEffect(active ? engine.coverScale(frame, at: timeline.date) : 1)
                .background {
                    Canvas { context, size in
                        let coverSize = CGSize(width: size.width - Self.margin * 2, height: size.height - Self.margin * 2)
                        let side = min(coverSize.width, coverSize.height)
                        RadialBars.draw(frame, in: &context, centre: CGPoint(x: size.width / 2, y: size.height / 2),
                                        inner: side / 2 + 5, reach: side * 0.34, colour: colour)
                    }
                    .padding(-Self.margin)
                    .opacity(active ? 1 : 0)
                    .allowsHitTesting(false)
                }
        }
    }
}
