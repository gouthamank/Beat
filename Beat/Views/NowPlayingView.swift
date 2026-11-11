import SwiftUI

/// Hosts the full Now Playing view over the whole window, morphing it out of the now-playing bar and back.
/// Lives on the split view, outside the navigation stack, because pushed pages cover the stack's overlays.
struct NowPlayingOverlay: View {
    @Environment(AppNavigator.self) private var navigator
    @Environment(PlaybackQueue.self) private var queue
    @State private var origin = FrameProbe()
    @State private var visible = false
    @State private var expanded = false
    /// The bar's frame in this overlay's coordinates, captured when opening and closing.
    @State private var barRect: CGRect?

    var body: some View {
        GeometryReader { proxy in
            if visible, let track = queue.current {
                let full = CGRect(origin: .zero, size: proxy.size)
                let rect = expanded ? full : (barRect ?? fallbackBar(in: proxy.size))
                // Laid out at full size and revealed by the growing frame, so its layout never squashes.
                NowPlayingView(track: track, contentOpacity: expanded ? 1 : 0)
                    .frame(width: full.width, height: full.height)
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(RoundedRectangle(cornerRadius: expanded ? 0 : 24, style: .continuous))
                    // From the outline: SwiftUI's `.shadow` shadowed all of Now Playing (lyrics, visualizer)
                    // and redrew it with every frame they changed, even faded out once expanded.
                    .background(ShapeShadow(shape: RoundedRectangle(cornerRadius: expanded ? 0 : 24, style: .continuous),
                                            opacity: expanded ? 0 : 0.25, radius: 16, y: 6))
                    .offset(x: rect.minX, y: rect.minY)
            }
        }
        .background { Color.clear.frameProbe(origin) }
        .ignoresSafeArea()
        .allowsHitTesting(visible)
        .onChange(of: navigator.showingNowPlaying) { _, show in show ? open() : close() }
        .onChange(of: queue.current == nil) { _, stopped in
            if stopped { navigator.showingNowPlaying = false }
        }
    }

    private func open() {
        guard queue.current != nil else {
            navigator.showingNowPlaying = false
            return
        }
        barRect = currentBarRect()
        expanded = false
        visible = true
        // Grow on the next frame, so it starts from the bar rather than appearing full size.
        Task { @MainActor in
            withAnimation(Motion.morphOpen) { expanded = true }
        }
    }

    private func close() {
        barRect = currentBarRect()
        withAnimation(Motion.morphClose) {
            expanded = false
        } completion: {
            if !navigator.showingNowPlaying { visible = false }
        }
    }

    private func currentBarRect() -> CGRect? {
        guard let bar = navigator.barProbe?.windowRect else { return nil }
        let base = origin.windowRect?.origin ?? .zero
        return bar.offsetBy(dx: -base.x, dy: -base.y)
    }

    /// Where the bar usually is, if it couldn't be measured.
    private func fallbackBar(in size: CGSize) -> CGRect {
        let width = min(880, size.width - 40)
        return CGRect(x: (size.width - width) / 2, y: size.height - 84, width: width, height: 70)
    }
}

/// Big artwork and the transport, optionally beside lyrics, on the cover's colours.
struct NowPlayingView: View {
    let track: Track
    var contentOpacity: Double = 1
    @Environment(PlaybackQueue.self) private var queue
    @Environment(AppNavigator.self) private var navigator
    @Environment(ArtworkCache.self) private var artwork
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.playbackAccent) private var playbackAccent
    @AppStorage("appearance.coverColours") private var coverColours = true
    @AppStorage("nowPlaying.showLyrics") private var showLyrics = false
    @AppStorage("visualizer.style") private var visualizerStyle = VisualizerStyle.pulse.rawValue
    @State private var visualizing = false
    @State private var controlsVisible = true
    @State private var hideControls: Task<Void, Never>?
    @State private var extracted: ArtworkPalette?

    /// The cover's colours, unless the Plain appearance is chosen in Settings.
    private var palette: ArtworkPalette? { coverColours ? extracted : nil }

    private var primary: AnyShapeStyle { palette.map { AnyShapeStyle($0.primary.color) } ?? AnyShapeStyle(.primary) }
    private var secondary: AnyShapeStyle { palette.map { AnyShapeStyle($0.secondary.color) } ?? AnyShapeStyle(.secondary) }

    var body: some View {
        ZStack {
            if visualizing {
                visualizerScreen
                    .transition(.opacity)
            } else {
                HStack(spacing: 56) {
                    player
                        .frame(maxWidth: showLyrics ? 400 : 520)
                    if showLyrics {
                        LyricsView(track: track, palette: palette)
                            .frame(maxWidth: 560, maxHeight: 640)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.45, bounce: 0.1), value: showLyrics)
                .padding(48)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Dragging down anywhere that isn't a control closes it. A click does nothing.
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 10, coordinateSpace: .global).onEnded { value in
                        if NowPlayingDrag.passes(value, upward: false) { navigator.showingNowPlaying = false }
                    }
                )
                .overlay(alignment: .topLeading) { closeButton }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: visualizing)
        .opacity(contentOpacity)
        .background { backdrop }
        // Controls and glass follow the cover's lightness rather than the system's.
        .environment(\.colorScheme, palette.map { $0.isDark ? ColorScheme.dark : .light } ?? colorScheme)
        // On the cover's own colours, playback controls use the colour chosen to read on them.
        .environment(\.playbackAccent, palette?.primary.color ?? playbackAccent)
        // The playing track's own art and colours: an album whose tracks carry different art changes with each.
        .task(id: ArtworkSource(track)) {
            // Opening, the colours apply at once: animated, the whole view re-laid out inside that animation and
            // the title slid down from the top of the cover while it grew out of the bar. Changing songs while
            // open, they cross-fade.
            let fade: Animation? = extracted == nil ? nil : .easeInOut(duration: 0.6)
            if let cached = artwork.cachedPalette(ArtworkSource(track)) {
                withAnimation(fade) { extracted = cached }
                return
            }
            let found = await artwork.palette(ArtworkSource(track))
            withAnimation(fade) { extracted = found }
        }
    }

    private var player: some View {
        VStack(spacing: 22) {
                // Original shape, so wide covers aren't cropped; the frame caps whichever side is longer.
                ArtworkView(track: track, size: .large, cornerRadius: 16, framing: .original)
                    .frame(maxWidth: showLyrics ? 400 : 640, maxHeight: showLyrics ? 340 : 440)
                    .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
                VStack(spacing: 4) {
                    Text(track.title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .foregroundStyle(primary)
                    Text(track.displayArtist)
                        .font(.title3)
                        .foregroundStyle(secondary)
                        .lineLimit(1)
                    Button(track.album) {
                        navigator.showingNowPlaying = false
                        navigator.openAlbum(track.albumID)
                    }
                    .buttonStyle(.plain)
                    .font(.callout)
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .help("Show Album")
                }
                VStack(spacing: 12) {
                    Scrubber(duration: track.duration)
                    TransportControls()
                        .scaleEffect(1.3)
                        .padding(.vertical, 6)
                    HStack(spacing: 14) {
                        ModeControls()
                        Button { showLyrics.toggle() } label: {
                            Image(systemName: "quote.bubble")
                                .foregroundStyle(showLyrics ? palette?.primary.color ?? playbackAccent : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(showLyrics ? "Hide Lyrics" : "Show Lyrics")
                        Button { visualizing = true } label: {
                            Image(systemName: "waveform").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("v", modifiers: [.command, .shift])
                        .help("Visualizer (⇧⌘V)")
                    }
                }
                .frame(maxWidth: 420)
        }
    }

    // MARK: Visualizer mode

    private var style: VisualizerStyle { VisualizerStyle(rawValue: visualizerStyle) ?? .pulse }

    /// The visualization fills the view; controls fade out after 3 s without mouse movement.
    private var visualizerScreen: some View {
        ZStack {
            VisualizerView(track: track, palette: palette, style: style)
            VStack {
                HStack {
                    circleButton("chevron.left", help: "Leave Visualizer (Esc or ⇧⌘V)") { visualizing = false }
                        .keyboardShortcut(.cancelAction)
                        // ⇧⌘V leaves too, as it entered; a view takes one shortcut, so it gets a hidden button.
                        .background {
                            Button("Leave Visualizer") { visualizing = false }
                                .keyboardShortcut("v", modifiers: [.command, .shift])
                                // Invisible but present: a `.hidden()` button can lose its shortcut.
                                .opacity(0)
                                .frame(width: 0, height: 0)
                                .accessibilityHidden(true)
                        }
                    Spacer()
                    Picker("Style", selection: $visualizerStyle) {
                        ForEach(VisualizerStyle.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 340)
                    Spacer()
                    // The chevron's width, so the style picker stays centred.
                    Color.clear.frame(width: 36, height: 36)
                }
                Spacer()
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.headline).foregroundStyle(primary).lineLimit(1)
                        Text(track.displayArtist).font(.subheadline).foregroundStyle(secondary).lineLimit(1)
                        if queue.output.isExternal {
                            Text("Out of sync on AirPlay").font(.caption).foregroundStyle(secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(spacing: 8) {
                        Scrubber(duration: track.duration)
                        TransportControls()
                    }
                    .frame(width: 380)
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 44)
            .padding(.bottom, 28)
            .opacity(controlsVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.4), value: controlsVisible)
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase { revealControls() }
        }
        .onAppear { revealControls() }
        .onDisappear {
            hideControls?.cancel()
            controlsVisible = true
        }
    }

    private func revealControls() {
        if !controlsVisible { controlsVisible = true }
        hideControls?.cancel()
        hideControls = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            controlsVisible = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    private func circleButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .beatGlass(in: Circle(), interactive: true)
        .help(help)
    }

    private var closeButton: some View {
            Button { navigator.showingNowPlaying = false } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .beatGlass(in: Circle(), interactive: true)
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
            .padding(.leading, 20)
            .padding(.top, 44)
    }

    /// A vivid blur of the cover under a wash of the palette background; cross-fades between tracks.
    private var backdrop: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            ZStack {
                palette?.background.color
                ArtworkBackdrop(source: ArtworkSource(track), vividness: palette == nil ? .subtle : .vivid)
                // Keeps what's behind the text close to the colour its contrast was checked against.
                palette?.background.color.opacity(0.55)
            }
            .id(ArtworkSource(track))
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.6), value: ArtworkSource(track))
        .ignoresSafeArea()
    }
}
