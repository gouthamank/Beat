import AppKit
import SwiftUI

// The now-playing bar's AppKit pieces: the page column's frame, the progress fill and the playing bars.
// Core Animation does the work; iPad and iPhone have UIKit twins in Platform/iOS/BarLayers.swift.

/// Reports the page column's frame in window coordinates (top-left origin) whenever it moves or resizes:
/// window resizes, sidebar drags and the sidebar's collapse animation. Feeds `WindowNowPlayingBar`.
struct DetailColumnReader: NSViewRepresentable {
    let navigator: AppNavigator

    func makeNSView(context: Context) -> DetailColumnView {
        let view = DetailColumnView()
        view.report = { [weak navigator] in navigator?.detailColumnFrame = $0 }
        return view
    }

    func updateNSView(_ view: DetailColumnView, context: Context) {}
}

final class DetailColumnView: NSView {
    var report: ((CGRect) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var last: CGRect?

    /// Never takes clicks; it only measures.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        measure()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        // The column can move without resizing (the sidebar's divider), which doesn't lay this view out.
        for (name, object) in [(NSSplitView.didResizeSubviewsNotification, nil as Any?), (NSWindow.didResizeNotification, window)] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.measure() }
            })
        }
        measure()
    }

    private func measure() {
        guard let window, let content = window.contentView else { return }
        let r = convert(bounds, to: nil)
        let rect = CGRect(x: r.minX, y: content.bounds.height - r.maxY, width: r.width, height: r.height)
        guard rect != last else { return }
        last = rect
        report?(rect)
    }
}

struct BarProgressLayers: NSViewRepresentable {
    let elapsed: TimeInterval
    let duration: TimeInterval
    let isPlaying: Bool
    let color: NSColor
    let chapterStarts: [TimeInterval]
    let thick: Bool

    func makeNSView(context: Context) -> BarProgressView { BarProgressView() }

    func updateNSView(_ view: BarProgressView, context: Context) {
        view.update(elapsed: elapsed, duration: duration, isPlaying: isPlaying, color: color,
                    chapterStarts: chapterStarts, lineHeight: thick ? 6 : 3)
    }
}

final class BarProgressView: NSView {
    private let fill = CAGradientLayer()
    private let track = CALayer()
    private let line = CALayer()
    private let trackGaps = CAShapeLayer()
    private let lineGaps = CAShapeLayer()

    private var duration: TimeInterval = 0
    private var isPlaying = false
    private var color = NSColor.controlAccentColor
    private var chapterStarts: [TimeInterval] = []
    private var lineHeight: CGFloat = 3
    /// Where playback was at `anchorTime`; the animation runs on from here.
    private var anchorElapsed: TimeInterval = 0
    private var anchorTime: CFTimeInterval = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        guard let layer else { return }
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

    /// Clicks go to the bar.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        restart(at: currentElapsed)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColors()
    }

    /// Where the animation says playback is now.
    private var currentElapsed: TimeInterval {
        isPlaying ? anchorElapsed + (CACurrentMediaTime() - anchorTime) : anchorElapsed
    }

    func update(elapsed: TimeInterval, duration: TimeInterval, isPlaying: Bool, color: NSColor,
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
        effectiveAppearance.performAsCurrentDrawingAppearance {
            fill.colors = [color.withAlphaComponent(0.10).cgColor, color.withAlphaComponent(0.34).cgColor]
            line.backgroundColor = color.cgColor
            track.backgroundColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
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

struct PlayingBars: NSViewRepresentable {
    let isAnimating: Bool
    let color: NSColor

    func makeNSView(context: Context) -> PlayingBarsView { PlayingBarsView() }

    func updateNSView(_ view: PlayingBarsView, context: Context) {
        view.update(isAnimating: isAnimating, color: color)
    }
}

final class PlayingBarsView: NSView {
    private let bars = (0..<3).map { _ in CALayer() }
    private var color = NSColor.controlAccentColor
    private var isAnimating = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for bar in bars {
            bar.anchorPoint = CGPoint(x: 0.5, y: 0)
            bar.cornerRadius = 1.5
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Clicks go to the row underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            bar.bounds = CGRect(x: 0, y: 0, width: 3, height: isAnimating ? 8 : 5)
            bar.position = CGPoint(x: 1.5 + CGFloat(i) * 5, y: 0)
        }
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyColor()
    }

    func update(isAnimating: Bool, color: NSColor) {
        self.color = color
        applyColor()
        guard isAnimating != self.isAnimating else { return }
        self.isAnimating = isAnimating
        needsLayout = true
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
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let cgColor = color.cgColor
            for bar in bars { bar.backgroundColor = cgColor }
        }
        CATransaction.commit()
    }
}
