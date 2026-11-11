import SwiftUI

struct NowPlayingBar: View {
    /// Space scrolling content leaves at the bottom so it can scroll clear of the bar.
    static let reservedHeight: CGFloat = 96

    @Environment(PlaybackQueue.self) private var queue
    @Environment(AppNavigator.self) private var navigator
    @State private var probe = FrameProbe()
    /// How far the bar has lifted while being dragged up: a hint that the drag is noticed, not tracking.
    @State private var lift: CGFloat = 0

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
                        Scrubber(duration: track.duration)
                    }
                    .frame(maxWidth: .infinity)
                    ModeControls()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frameProbe(probe)
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
    @State private var dragValue: Double?

    var body: some View {
        let shown = dragValue ?? queue.currentTime
        HStack(spacing: 8) {
            timeLabel(shown.trackTime, alignment: .trailing)
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
            timeLabel("-" + max(duration - shown, 0).trackTime, alignment: .leading)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    /// Sized by a hidden copy of the widest time this track can show, so mixes over an hour
    /// don't wrap and the slider doesn't shift as the digits change.
    private func timeLabel(_ text: String, alignment: Alignment) -> some View {
        ZStack(alignment: alignment) {
            Text(duration >= 3600 ? "-0:00:00" : "-00:00").hidden()
            Text(text)
        }
        .lineLimit(1)
    }
}

struct ModeControls: View {
    @Environment(PlaybackQueue.self) private var queue

    var body: some View {
        @Bindable var queue = queue
        HStack(spacing: 14) {
            Button(action: queue.toggleShuffle) {
                Image(systemName: "shuffle")
                    .foregroundStyle(queue.isShuffled ? Color.accentColor : .secondary)
            }
            .help(queue.isShuffled ? "Shuffle On" : "Shuffle Off")
            Button(action: queue.cycleRepeat) {
                Image(systemName: queue.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(queue.repeatMode == .off ? .secondary : Color.accentColor)
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
