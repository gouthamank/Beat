import SwiftUI

enum VisualizerStyle: String, CaseIterable {
    case pulse, bars, radial, waveform

    var title: String { rawValue.capitalized }
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
}

/// The visualization itself, in one of four styles, coloured from the cover.
struct VisualizerView: View {
    let track: Track
    let palette: ArtworkPalette?
    let style: VisualizerStyle
    @Environment(PlaybackQueue.self) private var queue
    @State private var engine = VisualizerEngine()

    private var primary: Color { palette?.primary.color ?? .accentColor }
    private var secondary: Color { palette?.secondary.color ?? .secondary }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !queue.isPlaying && engine.isAtRest)) { _ in
            let frame = engine.next(samples: queue.samples, playing: queue.isPlaying)
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                ZStack {
                    Canvas { context, size in draw(frame, in: &context, size: size) }
                    if style == .pulse || style == .radial {
                        ArtworkView(track: track, size: .large, cornerRadius: 16)
                            .frame(width: side * (style == .pulse ? 0.42 : 0.34), height: side * (style == .pulse ? 0.42 : 0.34))
                            // From the outline, so the pulse doesn't redraw a blurred copy of the cover every frame.
                            .background(ShapeShadow(shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                                                    opacity: 0.35, radius: 24, y: 10))
                            .scaleEffect(style == .pulse ? 1 + CGFloat(frame.bass) * 0.03 : 1)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }

    private func draw(_ frame: SpectrumFrame, in context: inout GraphicsContext, size: CGSize) {
        switch style {
        case .pulse: drawPulse(frame, &context, size)
        case .bars: drawBars(frame, &context, size)
        case .radial: drawRadial(frame, &context, size)
        case .waveform: drawWaveform(frame, &context, size)
        }
    }

    /// A soft glow behind the cover that breathes with the bass.
    private func drawPulse(_ frame: SpectrumFrame, _ context: inout GraphicsContext, _ size: CGSize) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let side = min(size.width, size.height)
        let bass = CGFloat(frame.bass)
        let radius = side * 0.3 * (1 + bass * 0.6)
        context.drawLayer { layer in
            layer.addFilter(.blur(radius: 50))
            let rect = CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
            layer.fill(Path(ellipseIn: rect), with: .color(primary.opacity(0.25 + 0.55 * bass)))
        }
        // A thin ring that follows overall loudness.
        let ring = side * 0.26 * (1 + CGFloat(frame.level) * 0.25)
        let ringRect = CGRect(x: centre.x - ring, y: centre.y - ring, width: ring * 2, height: ring * 2)
        context.stroke(Path(ellipseIn: ringRect), with: .color(secondary.opacity(0.15 + 0.35 * Double(frame.level))), lineWidth: 2)
    }

    /// Rounded spectrum bars along the bottom, with a faint reflection.
    private func drawBars(_ frame: SpectrumFrame, _ context: inout GraphicsContext, _ size: CGSize) {
        let count = frame.bands.count
        guard count > 0 else { return }
        let usable = size.width * 0.86
        let gap: CGFloat = 3
        let width = max((usable - gap * CGFloat(count - 1)) / CGFloat(count), 1)
        let left = (size.width - usable) / 2
        let baseline = size.height * 0.7
        let maxHeight = size.height * 0.5
        let shading = GraphicsContext.Shading.linearGradient(
            Gradient(colors: [secondary, primary]),
            startPoint: CGPoint(x: 0, y: baseline), endPoint: CGPoint(x: 0, y: baseline - maxHeight)
        )
        for (i, value) in frame.bands.enumerated() {
            let height = max(CGFloat(value) * maxHeight, 3)
            let x = left + CGFloat(i) * (width + gap)
            let bar = Path(roundedRect: CGRect(x: x, y: baseline - height, width: width, height: height), cornerRadius: width / 2)
            context.fill(bar, with: shading)
            let reflection = Path(roundedRect: CGRect(x: x, y: baseline + 4, width: width, height: height * 0.3), cornerRadius: width / 2)
            context.fill(reflection, with: .color(primary.opacity(0.15)))
        }
    }

    /// Bars radiating in a ring around the cover, mirrored left and right.
    private func drawRadial(_ frame: SpectrumFrame, _ context: inout GraphicsContext, _ size: CGSize) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let side = min(size.width, size.height)
        let inner = side * 0.17 + 16
        let values = frame.bands + frame.bands.reversed()
        let step = 2 * Double.pi / Double(values.count)
        for (i, value) in values.enumerated() {
            let angle = Double(i) * step - .pi / 2
            let length = 6 + CGFloat(value) * side * 0.22
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            var line = Path()
            line.move(to: CGPoint(x: centre.x + direction.x * inner, y: centre.y + direction.y * inner))
            line.addLine(to: CGPoint(x: centre.x + direction.x * (inner + length), y: centre.y + direction.y * (inner + length)))
            context.stroke(line, with: .color(primary.opacity(0.4 + 0.6 * Double(value))),
                           style: StrokeStyle(lineWidth: 4, lineCap: .round))
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
