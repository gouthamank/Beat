import SwiftUI

struct NowPlayingBar: View {
    /// Space scrolling content leaves at the bottom so it can scroll clear of the bar.
    static let reservedHeight: CGFloat = 96

    @Environment(PlaybackQueue.self) private var queue
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.lyricsProvider) private var lyrics
    @Environment(\.playbackAccent) private var playbackAccent
    @Environment(\.compactLayout) private var compact
    /// The screen's bottom safe area (an iPhone's home indicator), which the window overlay ignores.
    var bottomInset: CGFloat = 0
    @State private var probe = FrameProbe()
    /// How far the bar has lifted while being dragged up: a hint that the drag is noticed, not tracking.
    @State private var lift: CGFloat = 0
    /// The playing file's tracklist, when its timed lyrics are one (a DJ mix).
    @State private var chapters: [MixChapter] = []
    /// The pointer is on the seek strip: the edge line thickens.
    @State private var seeking = false

    /// The playing cover's colour, or the system accent (see `\.playbackAccent`).
    private var progressColor: PlatformColor { PlatformColor(playbackAccent) }

    var body: some View {
        if let track = queue.current {
            BeatGlassContainer(spacing: 12) {
                row(track)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frameProbe(probe)
                // The progress: the glass fills with the cover's colour, and a line along the bottom edge
                // shows the same, with gaps at a mix's track starts. Core Animation moves both.
                .background {
                    // No gaps on a phone: at its size the segments read as clutter, not as a mix's tracks.
                    BarProgress(duration: track.duration, color: progressColor,
                                chapterStarts: compact ? [] : chapters.map(\.start), thick: seeking)
                }
                // One click on the bottom edge seeks there. Above the bar's open gesture, which gets the rest.
                .overlay { SeekStrip(duration: track.duration, chapters: chapters, hovering: $seeking) }
                .loadsMixChapters(of: track, into: $chapters)
                // The whole bar opens Now Playing, by a click or a drag up. Controls take their own clicks and
                // drags first, so this only gets the glass between them.
                .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .gesture(openGesture)
                .help("Show Now Playing")
                .beatGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .offset(y: lift)
            .frame(maxWidth: 880)
            .padding(.horizontal, compact ? 12 : 20)
            .padding(.bottom, (compact ? 8 : 14) + bottomInset)
            .onAppear { navigator.barProbe = probe }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// The Mac's full row, or on a phone the cover and title with play/pause and next: shuffle, repeat, the queue,
    /// volume and AirPlay are in Now Playing, a tap away.
    @ViewBuilder
    private func row(_ track: Track) -> some View {
        if compact {
            HStack(spacing: 6) {
                Button(action: open) {
                    TrackSummary(track: track)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .gesture(openGesture)
                }
                .buttonStyle(.plain)
                Button(action: queue.togglePlayPause) {
                    Image(systemName: queue.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(queue.isPlaying ? "Pause" : "Play")
                Button(action: queue.next) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Next")
            }
        } else {
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
    @Environment(\.compactLayout) private var compact
    @State private var origin = FrameProbe()

    var body: some View {
        // Read here, in the body: read inside a GeometryReader's closure, a new column frame didn't redraw the bar, so
        // it stayed put while the window resized until something else (a page change) redrew it.
        let column = navigator.detailColumnFrame
        #if os(macOS)
        bar(column: column, bottomInset: 0)
        #else
        // For the safe area: the bar's overlay below ignores it.
        GeometryReader { safe in
            // On a phone, just above the home indicator (the view's own safe area also counts the page's bottom bars),
            // or a little off the bottom edge on one with a home button, which has none.
            bar(column: column, bottomInset: compact ? max(windowBottomInset(), 6) : safe.safeAreaInsets.bottom)
        }
        #endif
    }

    private func bar(column measured: CGRect?, bottomInset: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)
            // Hidden until the column has been measured, so it never shows over the wrong place.
            // A phone shows one column at a time, full width: its measured frame lags behind push and pop
            // animations, which left the bar half off the screen.
            if let column = compact ? origin.windowRect : measured {
                let base = origin.windowRect?.origin ?? .zero
                NowPlayingBar(bottomInset: bottomInset)
                    // For UI tests, which find the bar and measure it against the page column.
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("nowPlayingBar")
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
            #if os(macOS)
            // The Mac's back swipe shows its own chevron; iPad and iPhone use the system's edge swipe.
            .overlay(alignment: .leading) { SwipeBackIndicator() }
            #endif
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
    /// A mix's tracks: the line splits at each one.
    var chapters: [MixChapter] = []
    @Environment(PlaybackQueue.self) private var queue
    @Environment(\.playbackAccent) private var playbackAccent
    @State private var dragValue: Double?

    var body: some View {
        let shown = dragValue ?? queue.currentTime
        HStack(spacing: 8) {
            TimeLabel(shown.trackTime, duration: duration, alignment: .trailing)
            if !chapters.isEmpty {
                ChapterScrubber(duration: duration, chapters: chapters, position: shown, dragValue: $dragValue, commit: commit)
            } else {
            #if os(macOS)
            Slider(
                value: Binding(get: { shown }, set: { dragValue = $0 }),
                in: 0...max(duration, 1)
            ) { editing in
                if !editing, let value = dragValue { commit(value) }
            }
            .controlSize(.mini)
            .tint(playbackAccent)
            #else
            TouchSlider(value: Binding(get: { shown }, set: { dragValue = $0 }), in: 0...max(duration, 1)) { editing in
                if !editing, let value = dragValue { commit(value) }
            }
            .tint(playbackAccent)
            #endif
            }
            TimeLabel("-" + max(duration - shown, 0).trackTime, duration: duration, alignment: .leading)
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    private func commit(_ value: Double) {
        queue.seek(to: value)
        dragValue = nil
    }
}


/// A mix's progress in Now Playing: the line split at each of its tracks, so you can see and pick one. A tap or drag
/// seeks; meanwhile (and under the pointer on the Mac) a bubble above the line shows the time and the track there,
/// above the finger, which covers the line itself.
struct ChapterScrubber: View {
    let duration: TimeInterval
    let chapters: [MixChapter]
    /// The time shown: playback's, or the drag's.
    let position: TimeInterval
    @Binding var dragValue: Double?
    let commit: (Double) -> Void
    @Environment(\.playbackAccent) private var playbackAccent
    @State private var pointer: CGFloat?
    @State private var dragX: CGFloat?

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let thick = dragX != nil || pointer != nil
            ZStack(alignment: .topLeading) {
                Canvas { context, size in draw(in: &context, size: size, thick: thick) }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        dragX = drag.location.x
                        dragValue = time(at: drag.location.x, width: width)
                    }
                    .onEnded { drag in
                        dragX = nil
                        commit(time(at: drag.location.x, width: width))
                    })
                #if os(macOS)
                .onContinuousHover { phase in
                    if case .active(let point) = phase { pointer = point.x } else { pointer = nil }
                }
                #endif
                if let x = dragX ?? pointer {
                    SeekBubble(time: time(at: x, width: width), chapters: chapters)
                        .fixedSize()
                        .position(x: min(max(x, 80), width - 80), y: -14)
                        .allowsHitTesting(false)
                }
            }
            .animation(.snappy(duration: 0.2), value: thick)
        }
        .frame(height: 24)
    }

    private func time(at x: CGFloat, width: CGFloat) -> TimeInterval {
        min(max(x / width, 0), 1) * duration
    }

    /// Where each segment starts and ends, as fractions of the line: 0, each track after the first, 1.
    private var edges: [Double] {
        let length = max(duration, 1)
        let starts: [Double] = chapters.map { $0.start / length }.filter { $0 > 0 && $0 < 1 }
        return [0] + starts + [1]
    }

    /// Each segment's track, filled with the playback colour up to the position.
    private func draw(in context: inout GraphicsContext, size: CGSize, thick: Bool) {
        let height: CGFloat = thick ? 7 : 4
        let y = (size.height - height) / 2
        let gap: CGFloat = 3
        let edges = edges
        let played = min(max(position / max(duration, 1), 0), 1) * size.width
        for i in 0..<(edges.count - 1) {
            let start = edges[i] * size.width + (i > 0 ? gap / 2 : 0)
            let end = edges[i + 1] * size.width - (i < edges.count - 2 ? gap / 2 : 0)
            guard end > start else { continue }
            let track = CGRect(x: start, y: y, width: end - start, height: height)
            context.fill(Path(roundedRect: track, cornerRadius: height / 2), with: .color(.primary.opacity(0.2)))
            if played > start {
                let fill = CGRect(x: start, y: y, width: min(played, end) - start, height: height)
                context.fill(Path(roundedRect: fill, cornerRadius: height / 2), with: .color(playbackAccent))
            }
        }
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
        SeekBubble(time: time, chapters: chapters)
    }
}

/// The time at a point of the progress line, with the mix track playing there: over the bar's seek strip and Now
/// Playing's mix line.
struct SeekBubble: View {
    let time: TimeInterval
    let chapters: [MixChapter]

    var body: some View {
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

extension View {
    /// Reads the track's tracklist, when its timed lyrics are one (a DJ mix), into `chapters`. Files and saved
    /// answers only: no network.
    func loadsMixChapters(of track: Track, into chapters: Binding<[MixChapter]>) -> some View {
        modifier(MixChapterLoader(track: track, chapters: chapters))
    }
}

private struct MixChapterLoader: ViewModifier {
    let track: Track
    @Binding var chapters: [MixChapter]
    @Environment(\.lyricsProvider) private var lyrics

    func body(content: Content) -> some View {
        content.task(id: track.id) {
            chapters = []
            guard let lyrics, case .synced(let lines) = await lyrics.lyrics(for: track, online: false) else { return }
            chapters = MixChapters.from(lines) ?? []
        }
    }
}

/// The bar's glass fill and bottom edge line. Core Animation runs them: while playing, each gets one linear
/// animation to the end of the song, restarted only on play/pause, a new track or a seek, so the 4-times-a-second
/// time updates cost nothing here (`PlayingIndicator` for why not SwiftUI).
/// Reads the playback time itself, so its 4-times-a-second changes update only this, not the whole bar.
private struct BarProgress: View {
    let duration: TimeInterval
    let color: PlatformColor
    let chapterStarts: [TimeInterval]
    let thick: Bool
    @Environment(PlaybackQueue.self) private var queue

    var body: some View {
        BarProgressLayers(elapsed: queue.currentTime, duration: duration, isPlaying: queue.isPlaying, color: color,
                          chapterStarts: chapterStarts, thick: thick)
    }
}

struct ModeControls: View {
    @Environment(PlaybackQueue.self) private var queue
    @Environment(\.playbackAccent) private var playbackAccent

    var body: some View {
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
            // The Mac's own player volume and mute; the system volume on iPad and iPhone (Platform/*/VolumeControl).
            VolumeControl()
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
        PlayingBars(isAnimating: isAnimating, color: PlatformColor(color))
            .frame(width: 13, height: 12)
            .accessibilityElement()
            .accessibilityLabel(isAnimating ? "Now playing" : "Paused")
    }
}
