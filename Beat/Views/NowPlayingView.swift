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
        // Next on the last song: close with the usual morph into the bar, which keeps the track.
        .onChange(of: queue.skippedPastEnd) { navigator.showingNowPlaying = false }
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
    /// Remembered in UserDefaults but held in `@State`: toggling an `@AppStorage` value from a click made the clicked
    /// button jump to its new place while the rest of the column slid (the write lands outside the animation).
    @State private var showLyrics = UserDefaults.standard.bool(forKey: "nowPlaying.showLyrics")
    /// Radial around the cover, toggled by clicking it. Behind the cover, so it moves nothing.
    @AppStorage("nowPlaying.radial") private var showRadial = false
    @AppStorage("visualizer.style") private var visualizerStyle = VisualizerStyle.horizon.rawValue
    @State private var visualizing = false
    @State private var controlsVisible = true
    @State private var hideControls: Task<Void, Never>?
    /// The style just stepped to with ← or →, named briefly in the middle of the screen.
    @State private var styleHint: VisualizerStyle?
    @State private var hideStyleHint: Task<Void, Never>?
    @State private var extracted: ArtworkPalette?
    /// The art shown (cover and backdrop): it follows the track once its colours, backdrop and cover are ready,
    /// and stays put when the next track carries the same picture.
    @State private var shownSource: ArtworkSource?
    /// `shownSource`'s art revision when it was shown (`ArtworkCache.revision(of:)`).
    @State private var shownRevision = 0
    /// Counts backdrop swaps; a new layer fades in above the old one, which stays until it's covered.
    @State private var backdropGeneration = 0

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
                .onChange(of: showLyrics) { UserDefaults.standard.set(showLyrics, forKey: "nowPlaying.showLyrics") }
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
        .environment(\.colorScheme, colorSchemeForCover)
        // On the cover's own colours, playback controls use the colour chosen to read on them.
        .environment(\.playbackAccent, palette?.primary.color ?? playbackAccent)
        // The playing track's own art and colours: an album whose tracks carry different art changes with each.
        // The revision too: a cover changed in Music while it plays is picked up.
        .task(id: ShownArt(source: ArtworkSource(track), revision: artwork.revision(of: ArtworkSource(track)))) {
            // Opening, the colours apply at once: animated, the whole view re-laid out inside that animation and
            // the title slid down from the top of the cover while it grew out of the bar. Changing songs while
            // open, they cross-fade.
            let source = ArtworkSource(track), revision = artwork.revision(of: source)
            // The same picture as the last track (tracks of one release each embedding it): nothing to change.
            // Cross-fading backdrop and cover into identical copies of themselves still read as a blur and unblur.
            // Unless it's this very art, changed in Music since it was shown.
            if let shown = shownSource, shown != source || revision == shownRevision, await artwork.samePicture(shown, source) {
                return
            }
            let fade: Animation? = extracted == nil ? nil : .easeInOut(duration: 0.6)
            var found = artwork.cachedPalette(source)
            if found == nil { found = await artwork.palette(source) }
            // The new backdrop is rendered before anything changes, so colours and backdrop swap in one
            // cross-fade; changing as each arrived (grey, then the image, then the colours) read as a flash.
            let key = BackdropImages.Key(source: source, vivid: coverColours && found != nil)
            if BackdropImages.cached(key) == nil { _ = await BackdropImages.image(key, artwork: artwork) }
            // The cover too, so it changes in the same cross-fade instead of fading in when it has loaded.
            _ = await artwork.image(source, size: .large)
            guard !Task.isCancelled else { return }
            withAnimation(fade) {
                extracted = found
                shownSource = source
                shownRevision = revision
                backdropGeneration += 1
            }
        }
    }

    private struct ShownArt: Hashable {
        let source: ArtworkSource
        let revision: Int
    }

    private var player: some View {
        VStack(spacing: 22) {
                // Original shape, so wide covers aren't cropped; the frame caps whichever side is longer.
                // Clicking it shows Radial around it.
                RadialCover(active: showRadial, colour: palette?.primary.color ?? playbackAccent) {
                    ArtworkView(source: shownSource ?? ArtworkSource(track), size: .large, cornerRadius: 16, framing: .original)
                        // From the outline: the cover scales with the music, and SwiftUI's `.shadow` would redraw.
                        .background(ShapeShadow(shape: RoundedRectangle(cornerRadius: 16, style: .continuous),
                                                opacity: 0.35, radius: 30, y: 14))
                }
                .animation(.easeInOut(duration: 0.3), value: showRadial)
                .contentShape(Rectangle())
                .onTapGesture { showRadial.toggle() }
                .help("Show or hide the spectrum")
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("Cover")
                .accessibilityHint("Shows or hides the spectrum around the cover")
                .frame(maxWidth: showLyrics ? 400 : 640, maxHeight: showLyrics ? 340 : 440)
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
                                // The clicked button hands its label the change without the column's animation (it's
                                // mid-click), so the icon jumped to its new place while everything else slid.
                                .animation(.spring(duration: 0.45, bounce: 0.1), value: showLyrics)
                        }
                        .buttonStyle(.plain)
                        .help("Lyrics")
                        .accessibilityValue(showLyrics ? "On" : "Off")
                        Button { visualizing = true } label: {
                            Image(systemName: "waveform").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut("v", modifiers: [.command, .shift])
                        .help("Visualizer (⇧⌘V)")
                    }
                    // The file's format, quietly, a little apart from the controls.
                    if let format = track.formatSummary {
                        Text(format)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(secondary)
                            .opacity(0.7)
                            .padding(.top, 10)
                            .accessibilityLabel("Format: \(format)")
                    }
                }
                .frame(maxWidth: 420)
        }
    }

    // MARK: Visualizer mode

    /// A saved style that no longer exists (Pulse) falls back to Horizon.
    private var style: VisualizerStyle { VisualizerStyle(rawValue: visualizerStyle) ?? .horizon }

    /// The visualization fills the view; controls fade out after 3 s without mouse movement.
    private var visualizerScreen: some View {
        ZStack {
            VisualizerView(palette: palette, style: style)
            VStack {
                HStack {
                    circleButton("chevron.left", help: "Leave Visualizer (Esc or ⇧⌘V)") { visualizing = false }
                        .keyboardShortcut(.cancelAction)
                        // ⇧⌘V leaves too, as it entered; a view takes one shortcut, so it gets a hidden button.
                        .background {
                            // Invisible but present: a `.hidden()` button can lose its shortcut.
                            Group {
                                Button("Leave Visualizer") { visualizing = false }
                                    .keyboardShortcut("v", modifiers: [.command, .shift])
                                Button("Previous Style") { stepStyle(by: -1) }
                                    .keyboardShortcut(.leftArrow, modifiers: [])
                                Button("Next Style") { stepStyle(by: 1) }
                                    .keyboardShortcut(.rightArrow, modifiers: [])
                            }
                            .opacity(0)
                            .frame(width: 0, height: 0)
                            .accessibilityHidden(true)
                        }
                    Spacer()
                    // Bound to the style shown, not the saved name: a saved style that's since been removed matched
                    // no item, so the menu showed nothing selected while Horizon played.
                    Picker("Style", selection: Binding(get: { style }, set: { visualizerStyle = $0.rawValue })) {
                        ForEach(VisualizerStyle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    // A menu for now: ten styles don't fit a segmented control.
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 200)
                    Spacer()
                    // The chevron's width, so the style picker stays centred.
                    Color.clear.frame(width: 36, height: 36)
                }
                Spacer()
                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).font(.headline).foregroundStyle(style.isScene ? AnyShapeStyle(.white) : primary).lineLimit(1)
                        Text(track.displayArtist).font(.subheadline).foregroundStyle(captionStyle).lineLimit(1)
                        if queue.output.isExternal {
                            Text("Out of sync on AirPlay").font(.caption).foregroundStyle(captionStyle)
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
            // Scenes draw their own dark ground, whatever the cover's lightness: controls go dark to match, and
            // playback colour uses a cover colour that shows up on it.
            .environment(\.colorScheme, style.isScene ? .dark : colorSchemeForCover)
            .environment(\.playbackAccent, style.isScene ? SceneColours(palette: palette).accent.color : palette?.primary.color ?? playbackAccent)
            .opacity(controlsVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.4), value: controlsVisible)
            if let styleHint {
                Text(styleHint.title)
                    .font(.title2.weight(.semibold))
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .beatGlass(in: Capsule())
                    .environment(\.colorScheme, styleHint.isScene ? .dark : colorSchemeForCover)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: styleHint)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase { revealControls() }
        }
        .onAppear { revealControls() }
        .onDisappear {
            hideControls?.cancel()
            controlsVisible = true
            hideStyleHint?.cancel()
            styleHint = nil
        }
    }

    private var captionStyle: AnyShapeStyle { style.isScene ? AnyShapeStyle(.white.opacity(0.7)) : secondary }

    /// The colour scheme the rest of Now Playing uses (see `body`).
    private var colorSchemeForCover: ColorScheme { palette.map { $0.isDark ? ColorScheme.dark : .light } ?? colorScheme }

    /// ← and →: the previous or next style, wrapping round, named for a moment.
    private func stepStyle(by offset: Int) {
        let next = style.stepped(by: offset)
        visualizerStyle = next.rawValue
        styleHint = next
        revealControls()
        hideStyleHint?.cancel()
        hideStyleHint = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            styleHint = nil
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
                ArtworkBackdrop(source: shownSource ?? ArtworkSource(track), vividness: palette == nil ? .subtle : .vivid)
                // Keeps what's behind the text close to the colour its contrast was checked against.
                palette?.background.color.opacity(0.55)
            }
            .id(backdropGeneration)
            .zIndex(Double(backdropGeneration))
            // The old layer stays opaque underneath until the new one has faded in: fading both at once let the
            // window colour show through halfway.
            .transition(.asymmetric(insertion: .opacity,
                                    removal: .opacity.animation(.linear(duration: 0).delay(0.6))))
        }
        // No `.animation` here: the swap carries its own (none when opening, a cross-fade when changing songs).
        .ignoresSafeArea()
    }
}
