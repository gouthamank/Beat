import SwiftUI

struct NowPlayingBar: View {
    /// Space scrolling content leaves at the bottom so it can scroll clear of the bar.
    static let reservedHeight: CGFloat = 96

    @Environment(PlaybackQueue.self) private var queue
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.lyricsProvider) private var lyrics
    @Environment(\.playbackAccent) private var playbackAccent
    @State private var probe = FrameProbe()
    /// How far the bar has lifted while being dragged up: a hint that the drag is noticed, not tracking.
    @State private var lift: CGFloat = 0
    /// The playing file's tracklist, when its timed lyrics are one (a DJ mix).
    @State private var chapters: [MixChapter] = []
    /// The pointer is on the seek strip: the edge line thickens.
    @State private var seeking = false

    /// The playing cover's colour, or the system accent (see `\.playbackAccent`).
    private var progressColor: NSColor { NSColor(playbackAccent) }

    var body: some View {
        if let track = queue.current {
            BeatGlassContainer(spacing: 12) {
                HStack(spacing: 16) {
                    // A button so Tab reaches it and Space opens Now Playing; mouse clicks and drags on it go to
                    // the bar's gesture, like everywhere else on the bar.
                    Button(action: open) {
                        TrackSummary(track: track)
                            .frame(width: 210, alignment: .leading)
                            .contentShape(Rectangle())
                            .gesture(openGesture)
                    }
                    .buttonStyle(.plain)
                    VStack(spacing: 4) {
                        TransportControls()
                        BarTimes(duration: track.duration)
                    }
                    .frame(maxWidth: .infinity)
                    ModeControls()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frameProbe(probe)
                // The progress: the glass fills with the cover's colour, and a line along the bottom edge
                // shows the same, with gaps at a mix's track starts. Core Animation moves both.
                .background {
                    BarProgress(duration: track.duration, color: progressColor, chapterStarts: chapters.map(\.start), thick: seeking)
                }
                // One click on the bottom edge seeks there. Above the bar's open gesture, which gets the rest.
                .overlay { SeekStrip(duration: track.duration, chapters: chapters, hovering: $seeking) }
                // A tracklist stored as lyrics becomes chapters. Files and saved answers only: no network.
                .task(id: track.id) {
                    chapters = []
                    guard let lyrics, case .synced(let lines) = await lyrics.lyrics(for: track, online: false) else { return }
                    chapters = MixChapters.from(lines) ?? []
                }
                // The whole bar opens Now Playing, by a click or a drag up. Controls take their own clicks and
                // drags first, so this only gets the glass between them.
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .gesture(openGesture)
                .help("Show Now Playing")
                .beatGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .offset(y: lift)
            .frame(maxWidth: 880)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            .onAppear { navigator.barProbe = probe }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func open() {
        navigator.barProbe = probe
        navigator.showingNowPlaying = true
    }

    /// A click, or a drag up past `NowPlayingDrag.threshold`. Global coordinates, because the lift moves the
    /// bar under the pointer.
    private var openGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in lift = max(-12, min(0, value.translation.height * 0.25)) }
            .onEnded { value in
                withAnimation(.spring(duration: 0.3)) { lift = 0 }
                if NowPlayingDrag.isClick(value) || NowPlayingDrag.passes(value, upward: true) { open() }
            }
    }
}

/// Dragging the bar up opens Now Playing; dragging Now Playing down closes it. Not finger-tracking: past the
/// threshold the usual morph runs.
enum NowPlayingDrag {
    /// How far a drag has to go. Tune here.
    static let threshold: CGFloat = 50
    /// Less movement than this is a click.
    static let clickSlop: CGFloat = 5

    static func isClick(_ value: DragGesture.Value) -> Bool {
        hypot(value.translation.width, value.translation.height) < clickSlop
    }

    /// Far enough, or flicked: the predicted end of a quick flick counts at twice the threshold.
    static func passes(_ value: DragGesture.Value, upward: Bool) -> Bool {
        let sign: CGFloat = upward ? -1 : 1
        return sign * value.translation.height > threshold || sign * value.predictedEndTranslation.height > threshold * 2
    }
}

/// The window's one now-playing bar, drawn over the split view and placed over the page column. Pushed
/// `NavigationStack` pages are layered above anything attached to the stack, so the bar can't live there;
/// over the split view it stays above them (like `HeroOverlay`), holds still while pages slide in and out,
/// and is the only copy updating. The column's frame comes from `DetailColumnReader`.
struct WindowNowPlayingBar: View {
    @Environment(PlaybackQueue.self) private var queue
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.colorScheme) private var colorScheme
    @State private var origin = FrameProbe()

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            // Hidden until the column has been measured, so it never shows over the wrong place.
            if let column = navigator.detailColumnFrame {
                let base = origin.windowRect?.origin ?? .zero
                NowPlayingBar()
                    // Over an album page's colours the bar's glass follows the cover's lightness, like the page does.
                    .environment(\.colorScheme, navigator.coverTint.current.map { $0.palette.isDark ? .dark : .light } ?? colorScheme)
                    .frame(width: column.width, height: column.height, alignment: .bottom)
                    .offset(x: column.minX - base.x, y: column.minY - base.y)
            }
        }
        .background { Color.clear.frameProbe(origin) }
        .ignoresSafeArea()
        .animation(.spring(duration: 0.4), value: queue.current == nil)
    }
}

extension View {
    /// Room at the bottom of a page for the window's now-playing bar, so scrolling content clears it, and the
    /// swipe-back chevron. Per page: an overlay on the stack would sit under pushed pages.
    func nowPlayingBarSpace() -> some View { modifier(NowPlayingBarSpace()) }
}

private struct NowPlayingBarSpace: ViewModifier {
    @Environment(PlaybackQueue.self) private var queue

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, queue.current == nil ? 0 : NowPlayingBar.reservedHeight, for: .scrollContent)
            .overlay(alignment: .leading) { SwipeBackIndicator() }
            .animation(.spring(duration: 0.4), value: queue.current == nil)
    }
}

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

private struct TrackSummary: View {
    let track: Track

    var body: some View {
        HStack(spacing: 10) {
            ArtworkView(track: track, cornerRadius: 7)
                .frame(width: 46, height: 46)
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(track.displayArtist)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .id(track.id)
        .transition(.opacity)
    }
}

struct TransportControls: View {
    @Environment(PlaybackQueue.self) private var queue

    var body: some View {
        HStack(spacing: 22) {
            Button(action: queue.previous) { Image(systemName: "backward.fill") }
                .help("Previous")
            Button(action: queue.togglePlayPause) {
                Image(systemName: queue.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 26)
            }
            .help(queue.isPlaying ? "Pause" : "Play")
            Button(action: queue.next) { Image(systemName: "forward.fill") }
                .help("Next")
        }
        .font(.system(size: 15))
        .buttonStyle(.plain)
    }
}

struct Scrubber: View {
    let duration: TimeInterval
    @Environment(PlaybackQueue.self) private var queue
    @Environment(\.playbackAccent) private var playbackAccent
    @State private var dragValue: Double?

    var body: some View {
        let shown = dragValue ?? queue.currentTime
        HStack(spacing: 8) {
            TimeLabel(shown.trackTime, duration: duration, alignment: .trailing)
            Slider(
                value: Binding(get: { shown }, set: { dragValue = $0 }),
                in: 0...max(duration, 1)
            ) { editing in
                if !editing, let value = dragValue {
                    queue.seek(to: value)
                    dragValue = nil
                }
            }
            .controlSize(.mini)
            .tint(playbackAccent)
            TimeLabel("-" + max(duration - shown, 0).trackTime, duration: duration, alignment: .leading)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

/// A time, sized by a hidden copy of the widest time this track can show, so mixes over an hour don't wrap
/// and nothing beside it shifts as the digits change.
struct TimeLabel: View {
    let text: String
    let duration: TimeInterval
    let alignment: Alignment

    init(_ text: String, duration: TimeInterval, alignment: Alignment) {
        self.text = text
        self.duration = duration
        self.alignment = alignment
    }

    var body: some View {
        ZStack(alignment: alignment) {
            Text(duration >= 3600 ? "-0:00:00" : "-00:00").hidden()
            Text(text)
        }
        .lineLimit(1)
    }
}

/// The bar's elapsed and remaining times, always showing, under the transport buttons.
private struct BarTimes: View {
    let duration: TimeInterval
    @Environment(PlaybackQueue.self) private var queue

    var body: some View {
        HStack {
            TimeLabel(queue.currentTime.trackTime, duration: duration, alignment: .leading)
            Spacer(minLength: 12)
            TimeLabel("-" + max(duration - queue.currentTime, 0).trackTime, duration: duration, alignment: .trailing)
        }
        .frame(maxWidth: 220)
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}

/// A clear strip along the bar's bottom edge: one click seeks to that point. Hovering thickens the edge line
/// and shows the time under the pointer above the bar, with the track there in a mix.
private struct SeekStrip: View {
    let duration: TimeInterval
    let chapters: [MixChapter]
    @Binding var hovering: Bool
    @Environment(PlaybackQueue.self) private var queue
    @State private var pointer: CGFloat?

    static let height: CGFloat = 10

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .bottomLeading) {
                Color.clear.allowsHitTesting(false)
                Color.clear
                    .frame(height: Self.height)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let point):
                            pointer = point.x
                            if !hovering { hovering = true }
                        case .ended:
                            pointer = nil
                            hovering = false
                        }
                    }
                    .gesture(SpatialTapGesture().onEnded { value in
                        queue.seek(to: min(max(value.location.x / width, 0), 1) * duration)
                    })
                if let pointer {
                    bubble(at: min(max(pointer / width, 0), 1) * duration)
                        .fixedSize()
                        .position(x: min(max(pointer, 70), width - 70), y: -16)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func bubble(at time: TimeInterval) -> some View {
        HStack(spacing: 6) {
            Text(time.trackTime).monospacedDigit()
            if let chapter = MixChapters.chapter(at: time, in: chapters) {
                Text(chapter.title).foregroundStyle(.white.opacity(0.7)).lineLimit(1).frame(maxWidth: 320)
            }
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// The bar's glass fill and bottom edge line. Core Animation runs them: while playing, each gets one linear
/// animation to the end of the song, restarted only on play/pause, a new track or a seek, so the 4-times-a-second
/// time updates cost nothing here (`PlayingIndicator` for why not SwiftUI).
/// Reads the playback time itself, so its 4-times-a-second changes update only this, not the whole bar.
private struct BarProgress: View {
    let duration: TimeInterval
    let color: NSColor
    let chapterStarts: [TimeInterval]
    let thick: Bool
    @Environment(PlaybackQueue.self) private var queue

    var body: some View {
        BarProgressLayers(elapsed: queue.currentTime, duration: duration, isPlaying: queue.isPlaying, color: color,
                          chapterStarts: chapterStarts, thick: thick)
    }
}

private struct BarProgressLayers: NSViewRepresentable {
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

struct ModeControls: View {
    @Environment(PlaybackQueue.self) private var queue
    @Environment(\.playbackAccent) private var playbackAccent

    var body: some View {
        @Bindable var queue = queue
        HStack(spacing: 14) {
            Button(action: queue.toggleShuffle) {
                Image(systemName: "shuffle")
                    .foregroundStyle(queue.isShuffled ? playbackAccent : .secondary)
            }
            .help(queue.isShuffled ? "Shuffle On" : "Shuffle Off")
            Button(action: queue.cycleRepeat) {
                Image(systemName: queue.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(queue.repeatMode == .off ? .secondary : playbackAccent)
            }
            .help("Repeat: \(queue.repeatMode.rawValue.capitalized)")
            QueueButton()
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
            RoutePicker(route: queue.output)
                .frame(width: 22, height: 22)
                .keyboardHighlight(queue.output.hasFocus, cornerRadius: 4)
                .help("Output")
        }
        .buttonStyle(.plain)
    }
}

/// Animated equalizer bars marking the playing track. Freezes when paused.
/// Three bouncing bars beside the playing track. Core Animation runs them, so they cost the main thread
/// nothing: a SwiftUI `TimelineView` re-rendered and re-measured the whole page around them 30 times a second.
struct PlayingIndicator: View {
    var isAnimating: Bool
    var color: Color = .accentColor

    var body: some View {
        PlayingBars(isAnimating: isAnimating, color: NSColor(color))
            .frame(width: 13, height: 12)
            .accessibilityElement()
            .accessibilityLabel(isAnimating ? "Now playing" : "Paused")
    }
}

private struct PlayingBars: NSViewRepresentable {
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
