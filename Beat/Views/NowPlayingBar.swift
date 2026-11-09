import SwiftUI

struct NowPlayingBar: View {
    /// Space scrolling content leaves at the bottom so it can scroll clear of the bar.
    static let reservedHeight: CGFloat = 96

    @Environment(PlaybackQueue.self) private var queue
    @Environment(AppNavigator.self) private var navigator
    @State private var probe = FrameProbe()

    var body: some View {
        if let track = queue.current {
            BeatGlassContainer(spacing: 12) {
                HStack(spacing: 16) {
                    // A button, not a tap gesture, so Tab reaches it and Space opens Now Playing.
                    Button {
                        navigator.barProbe = probe
                        navigator.showingNowPlaying = true
                    } label: {
                        TrackSummary(track: track)
                            .frame(width: 210, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show Now Playing")
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
                .beatGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .frame(maxWidth: 880)
            .padding(.horizontal, 20)
            .padding(.bottom, 14)
            // The topmost page's bar appears last, so ⌘L morphs from the bar that's actually visible.
            .onAppear { navigator.barProbe = probe }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

extension View {
    /// Floats the now-playing bar over this page and lets its scrolling content clear the bar.
    /// Every navigation page hosts its own bar: on macOS a pushed page is layered above anything
    /// attached to the NavigationStack itself, so a single shared overlay gets covered.
    func nowPlayingBarHost() -> some View { modifier(NowPlayingBarHost()) }
}

private struct NowPlayingBarHost: ViewModifier {
    @Environment(PlaybackQueue.self) private var queue
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .contentMargins(.bottom, queue.current == nil ? 0 : NowPlayingBar.reservedHeight, for: .scrollContent)
            // Over an album page's colours the bar's glass follows the cover's lightness, like the page does.
            .overlay(alignment: .bottom) {
                NowPlayingBar()
                    .environment(\.colorScheme, navigator.coverTint.current.map { $0.palette.isDark ? .dark : .light } ?? colorScheme)
            }
            // Per page for the same reason as the bar: an overlay on the stack would sit under pushed pages.
            .overlay(alignment: .leading) { SwipeBackIndicator() }
            .animation(.spring(duration: 0.4), value: queue.current == nil)
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
                Image(systemName: "speaker.fill").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $queue.volume, in: 0...1)
                    .disabled(queue.output.isExternal)
                    .help(queue.output.isExternal ? "AirPlay volume is set from the speaker or the menu bar" : "Volume")
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
