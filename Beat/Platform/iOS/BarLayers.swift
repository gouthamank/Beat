import SwiftUI
import UIKit

// UIKit twins of the now-playing bar's AppKit pieces (Platform/macOS/BarLayers.swift). The layer code is the
// Mac's: each host layer is geometry-flipped so its sublayers use the Mac's bottom-left origin (the progress line
// along the bottom, the playing bars growing upwards), and colours re-resolve when Light/Dark changes.

extension UIView {
    /// Touches pass through; sublayers placed from the bottom-left, as on the Mac; colours follow Light/Dark.
    fileprivate func configureHostLayer(onAppearanceChange: @escaping @MainActor (UIView) -> Void) {
        isUserInteractionEnabled = false
        backgroundColor = .clear
        layer.isGeometryFlipped = true
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: UIView, _: UITraitCollection) in onAppearanceChange(view) }
    }
}

/// Reports the page column's frame in window coordinates (top-left origin) whenever it moves or resizes:
/// rotation, multitasking resizes and the sidebar showing or hiding. Feeds `WindowNowPlayingBar`.
struct DetailColumnReader: UIViewRepresentable {
    let navigator: AppNavigator

    func makeUIView(context: Context) -> DetailColumnView {
        let view = DetailColumnView()
        view.report = { [weak navigator] in navigator?.detailColumnFrame = $0 }
        return view
    }

    func updateUIView(_ view: DetailColumnView, context: Context) {}
}

final class DetailColumnView: UIView {
    var report: (@MainActor (CGRect) -> Void)?
    private var last: CGRect?

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Never takes touches; it only measures.
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        measure()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        measure()
    }

    private func measure() {
        guard let window else { return }
        let rect = convert(bounds, to: window)
        guard rect != last else { return }
        last = rect
        report?(rect)
    }
}

struct BarProgressLayers: UIViewRepresentable {
    let elapsed: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let color: UIColor
    let chapterStarts: [TimeInterval]
    let thick: Bool

    func makeUIView(context: Context) -> BarProgressView { BarProgressView() }

    func updateUIView(_ view: BarProgressView, context: Context) {
        view.update(elapsed: elapsed, duration: duration, isPlaying: isPlaying, color: color,
                    chapterStarts: chapterStarts, lineHeight: thick ? 6 : 3)
    }
}

final class BarProgressView: UIView {
    private func configureHost() {
        configureHostLayer { ($0 as? BarProgressView)?.applyColors() }
    }

    private let fill = CAGradientLayer()
    private let track = CALayer()
    private let line = CALayer()
    private let trackGaps = CAShapeLayer()
    private let lineGaps = CAShapeLayer()

    private var duration: TimeInterval = 0
    private var isPlaying = false
    private var color = UIColor.tintColor
    private var chapterStarts: [TimeInterval] = []
    private var lineHeight: CGFloat = 3
    /// Where playback was at `anchorTime`; the animation runs on from here.
    private var anchorElapsed: TimeInterval = 0
    private var anchorTime: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHost()
        // Clipped to the bar's glass, so the fill and line follow its rounded corners.
        layer.cornerRadius = 24
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        fill.startPoint = CGPoint(x: 0, y: 0.5)
        fill.endPoint = CGPoint(x: 1, y: 0.5)
        track.mask = trackGaps
        line.mask = lineGaps
        trackGaps.fillRule = .evenOdd
        lineGaps.fillRule = .evenOdd
        for sublayer in [fill, track, line] {
            // Grow rightwards from the leading edge.
            sublayer.anchorPoint = .zero
            layer.addSublayer(sublayer)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        restart(at: currentElapsed)
    }

    /// Where the animation says playback is now.
    private var currentElapsed: TimeInterval {
        isPlaying ? anchorElapsed + (CACurrentMediaTime() - anchorTime) : anchorElapsed
    }

    func update(elapsed: TimeInterval, duration: TimeInterval, isPlaying: Bool, color: UIColor,
                chapterStarts: [TimeInterval], lineHeight: CGFloat) {
        let restyle = color != self.color || chapterStarts != self.chapterStarts || lineHeight != self.lineHeight
        // A seek, or the player drifting, shows up as a gap between where it is and where the animation is.
        let restartNeeded = isPlaying != self.isPlaying || duration != self.duration || abs(currentElapsed - elapsed) > 0.5
        self.color = color
        self.chapterStarts = chapterStarts
        self.lineHeight = lineHeight
        self.duration = duration
        self.isPlaying = isPlaying
        if restyle { applyColors(); layoutLines() }
        if restartNeeded { restart(at: elapsed) }
    }

    private func applyColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        traitCollection.performAsCurrent {
            fill.colors = [color.withAlphaComponent(0.10).cgColor, color.withAlphaComponent(0.34).cgColor]
            line.backgroundColor = color.cgColor
            track.backgroundColor = UIColor.label.withAlphaComponent(0.12).cgColor
        }
        CATransaction.commit()
    }

    /// The edge line's height (animated by Core Animation when hovering changes it) and the chapter gaps.
    private func layoutLines() {
        let width = bounds.width
        track.bounds.size.height = lineHeight
        line.bounds.size.height = lineHeight
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.position = .zero
        line.position = .zero
        track.bounds.size.width = width
        let gaps = CGMutablePath()
        gaps.addRect(CGRect(x: 0, y: 0, width: width, height: 8))
        if duration > 0 {
            for start in chapterStarts where start > 0 && start < duration {
                gaps.addRect(CGRect(x: width * start / duration - 1, y: 0, width: 2, height: 8))
            }
        }
        for mask in [trackGaps, lineGaps] {
            mask.frame = CGRect(x: 0, y: 0, width: width, height: 8)
            mask.path = gaps
        }
        CATransaction.commit()
    }

    /// Sets both widths for `elapsed` and, while playing, animates them on to the end of the song.
    private func restart(at elapsed: TimeInterval) {
        anchorElapsed = elapsed
        anchorTime = CACurrentMediaTime()
        let width = bounds.width
        let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.position = .zero
        fill.bounds.size.height = bounds.height
        layoutLines()
        for layer in [fill, line] {
            layer.removeAnimation(forKey: "progress")
            layer.bounds.size.width = width * fraction
        }
        CATransaction.commit()
        guard isPlaying, duration > elapsed, width > 0 else { return }
        for layer in [fill, line] {
            let grow = CABasicAnimation(keyPath: "bounds.size.width")
            grow.fromValue = width * fraction
            grow.toValue = width
            grow.duration = duration - elapsed
            grow.timingFunction = CAMediaTimingFunction(name: .linear)
            grow.isRemovedOnCompletion = false
            grow.fillMode = .forwards
            layer.add(grow, forKey: "progress")
        }
    }
}

struct PlayingBars: UIViewRepresentable {
    let isAnimating: Bool
    let color: UIColor

    func makeUIView(context: Context) -> PlayingBarsView { PlayingBarsView() }

    func updateUIView(_ view: PlayingBarsView, context: Context) {
        view.update(isAnimating: isAnimating, color: color)
    }
}

final class PlayingBarsView: UIView {
    private func configureHost() {
        configureHostLayer { ($0 as? PlayingBarsView)?.applyColor() }
    }

    private let bars = (0..<3).map { _ in CALayer() }
    private var color = UIColor.tintColor
    private var isAnimating = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureHost()
        for bar in bars {
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.cornerRadius = 1.5
            layer.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: 3, height: isAnimating ? 8 : 5)
            bar.position = CGPoint(x: 1.5 + CGFloat(i) * 5, y: 0)
        }
        CATransaction.commit()
    }

    func update(isAnimating: Bool, color: UIColor) {
        self.color = color
        applyColor()
        guard isAnimating != self.isAnimating else { return }
        self.isAnimating = isAnimating
        setNeedsLayout()
        for (i, bar) in bars.enumerated() {
            guard isAnimating else { bar.removeAnimation(forKey: "bounce"); continue }
            // Each bar swings between 4 and 12 points like a sine wave, at its own speed and phase.
            let speed = 5 + Double(i) * 1.7 // radians per second
            let bounce = CABasicAnimation(keyPath: "bounds.size.height")
            bounce.fromValue = 4
            bounce.toValue = 12
            bounce.duration = .pi / speed
            bounce.autoreverses = true
            bounce.repeatCount = .infinity
            bounce.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            bounce.timeOffset = Double(i) * 1.3 / speed
            bounce.isRemovedOnCompletion = false
            bar.add(bounce, forKey: "bounce")
        }
    }

    private func applyColor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        traitCollection.performAsCurrent {
            let cgColor = color.cgColor
            for bar in bars { bar.backgroundColor = cgColor }
        }
        CATransaction.commit()
    }
}
