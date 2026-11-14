import SwiftUI

/// An artist's page: a header like an album page's (art, name, stats, Play/Shuffle, cover colours from
/// their most-played album), then Top Songs, Albums, Singles & EPs and Appears On. With artist info on in
/// Settings, what Discogs knows about them (photo, real name, bio, members, links) is part of the page:
/// the photo and real name in the header, the rest in About at the end, as in Apple Music.
struct ArtistDetailView: View {
    let artistID: String
    @Environment(LibraryStore.self) private var library
    @Environment(PlayHistoryStore.self) private var history
    @Environment(PlaybackQueue.self) private var queue
    @Environment(ArtworkCache.self) private var artwork
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.compactLayout) private var compact
    @Environment(\.artistInfoProvider) private var infoProvider
    @Environment(AppNavigator.self) private var navigator
    @Environment(HeroTransition.self) private var hero
    @Environment(ArtistImages.self) private var artistImages: ArtistImages?
    @AppStorage(ArtistInfoSettings.onlineKey) private var infoOnline = false
    /// Album section sort orders, shared by every artist page.
    @AppStorage(ArtistSorts.storageKey) private var sortsData: Data?
    @Environment(PageStore.self) private var pages
    /// The artist's own albums, songs and stats: built as the page appears, so it shows in the first frame.
    @State private var content: ArtistPageContent?
    /// Appears On scans the whole library, so it arrives a moment later (nil while it's being worked out).
    @State private var appearsOn: [Album]?
    /// How far the header has scrolled away, for the compact top bar.
    @State private var collapse = ScrollCollapse()
    @State private var scrolling = ScrollActivity()
    /// False while a zoom from a tile is landing, so the page fades in around the flying art.
    @State private var revealed = false
    /// The header art and the whole page, measured for the zoom and the colours' fade-out.
    @State private var artProbe = FrameProbe()
    @State private var pageProbe = FrameProbe()
    @State private var backgroundShown = false
    @State private var info: ArtistInfo?
    /// True until the first lookup answers, so "Find on Discogs…" doesn't flash before it.
    @State private var infoLoading = true
    /// This page's cover colours from `CoverTint`, the same source as the sidebar, once they're this page's.
    private var tint: CoverTint.Current? {
        navigator.coverTint.current.flatMap { $0.route == .artist(artistID) ? $0 : nil }
    }

    private var palette: ArtworkPalette? { tint?.palette }

    /// Controls, glass and text follow the cover's lightness once its colours show.
    private var pageScheme: ColorScheme {
        backgroundShown ? palette.map { $0.isDark ? .dark : .light } ?? colorScheme : colorScheme
    }

    var body: some View {
        if let artist = library.snapshot.artistsByID[artistID] {
            page(artist)
        } else {
            ContentUnavailableView("Artist Not Found", systemImage: "music.microphone")
        }
    }

    private func page(_ artist: Artist) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header(artist)
                if let content { sections(content) }
                // Still-loading parts hold their place with a shimmer instead of popping in later.
                if let appearsOn {
                    albumSection("Appears On", appearsOn, sort: .appearsOn, showsArtist: true)
                } else {
                    LoadingAlbumSection(title: "Appears On", palette: palette)
                }
                if let info {
                    ArtistAboutSection(artist: artist, info: info, palette: palette) { self.info = $0; artistImages?.refresh(artist.id) }
                } else if infoOnline {
                    if infoLoading {
                        LoadingAboutSection(palette: palette)
                    } else {
                        DiscogsFindLink(artist: artist) { self.info = $0; artistImages?.refresh(artist.id) }
                    }
                }
            }
            .coverPageContentPadding()
            // Full width from the start, so the header never sits centred while the page is still filling in.
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
            .pausesPointerWhileScrolling(scrolling)
            .followsKeyboardHighlight()
        }
        .tracksScrolling(scrolling)
        // As on album pages: while the art zooms in from a tile, the page fades in around it.
        .opacity(revealed ? 1 : 0)
        .onScrollGeometryChange(for: Double.self) {
            CoverPageTopBar.collapse(scrollOffset: $0.contentOffset.y + $0.contentInsets.top)
        } action: { _, progress in collapse.progress = progress }
        .background {
            // The tint's album (the same one the sidebar shows); with Plain, a soft blur of the featured album.
            // Window-aligned, like album pages, so the blur carries on into the sidebar.
            CoverPageBackground(albumID: tint?.albumID ?? content?.featuredAlbumID, palette: palette, shown: backgroundShown)
                .frameProbe(pageProbe)
        }
        .overlay(alignment: .top) { CoverPageTopBar(collapse: collapse, palette: palette) }
        // The page only, not the toolbar: the grid's search field kept this page's scheme after going back.
        .environment(\.colorScheme, pageScheme)
        .coverPageChrome()
        .coverPageToolbar(title: artist.name, collapse: collapse, palette: palette, scheme: pageScheme) {
            ArtistArtwork(albumIDs: artist.albumIDsNewestFirst, artistID: artist.id, cornerRadius: 0)
        }
        .navigationTitle(artist.name)
        .accessibilityIdentifier("artistPage")
        .onAppear {
            buildLocalContent(artist)
            hero.setTarget(artProbe, for: .artist(artist.id))
            registerPage(artist)
            if hero.isFlying(to: .artist(artist.id)) {
                withAnimation(Motion.fade) { revealed = true }
            } else {
                revealed = true
            }
            withAnimation(Motion.fade) { backgroundShown = true }
        }
        .onDisappear { backgroundShown = false }
        .onChange(of: contentKey(artist)) { buildLocalContent(artist) }
        .onChange(of: tint?.albumID) { registerPage(artist) }
        .task(id: contentKey(artist)) { await loadAppearsOn(artist) }
        .task(id: "\(artist.id)-\(infoOnline)") { await loadInfo(artist) }
    }

    // MARK: Header

    private func header(_ artist: Artist) -> some View {
        coverPageHeaderLayout(compact) {
            // Their downloaded photo, else the cover mosaic; the zoom from a tile lands here.
            ArtistArtwork(albumIDs: artist.albumIDsNewestFirst, artistID: artist.id, cornerRadius: HeroTransition.headerCornerRadius)
                .frame(width: 200, height: 200)
                .frameProbe(artProbe)
                // Drawn from the outline: SwiftUI's `.shadow` was redrawn on every scrolled frame.
                .background(ShapeShadow(shape: RoundedRectangle(cornerRadius: HeroTransition.headerCornerRadius, style: .continuous),
                                        opacity: 0.3, radius: 20, y: 10))
                // Hidden while the zoom's flying copy is on its way here (or back to its tile).
                .opacity(hero.isFlying(to: .artist(artist.id)) ? 0 : 1)

            VStack(alignment: compact ? .center : .leading, spacing: 6) {
                Text(artist.name)
                    .font(compact ? .title.bold() : .largeTitle.bold())
                    .foregroundStyle(palette?.primary.color ?? Color.primary)
                    .lineLimit(2)
                Text(statsLine(artist))
                    .font(.callout)
                    .foregroundStyle(palette.map { AnyShapeStyle($0.secondary.color) } ?? AnyShapeStyle(.secondary))
                let tracks = library.snapshot.tracks(of: artist)
                BeatGlassContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button { queue.play(tracks) } label: { Label("Play", systemImage: "play.fill").frame(minWidth: 70) }
                            .beatGlassButtonStyle(prominent: true)
                        Button { queue.play(tracks, shuffled: true) } label: { Label("Shuffle", systemImage: "shuffle").frame(minWidth: 70) }
                            .beatGlassButtonStyle()
                    }
                    .controlSize(.large)
                    .disabled(tracks.isEmpty)
                }
                .padding(.top, 10)
            }
            .multilineTextAlignment(compact ? .center : .leading)
        }
    }

    private func statsLine(_ artist: Artist) -> String {
        let albums = artist.albumIDs.count
        var parts = [albums.counted("album")]
        if let real = info?.artist.realname, !real.isEmpty, real.lowercased() != artist.name.lowercased() {
            parts.insert(real, at: 0)
        }
        if let content {
            parts.append(content.songCount.counted("song"))
            parts.append(Duration.seconds(content.duration).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
            if artist.fileSize > 0 { parts.append(artist.fileSize.fileSizeText) }
            if content.plays > 0 { parts.append(content.plays.counted("play")) }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Sections

    @ViewBuilder
    private func sections(_ content: ArtistPageContent) -> some View {
        if !content.topSongs.isEmpty {
            // Two columns side by side, or one on a phone, where two cut every title to a word.
            let columns = compact ? 1 : 2
            section("Top Songs") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: columns), spacing: 4) {
                    ForEach(Array(content.topSongs.enumerated()), id: \.element.id) { i, track in
                        SongCell(track: track, context: content.topSongs, index: i).keyboardGridItem(i)
                    }
                }
                .keyboardGrid(count: content.topSongs.count, layout: .order(.rows(columns: columns)), id: { content.topSongs[$0].id })
            }
        }
        albumSection("Albums", content.albums, sort: .albums, showsArtist: false)
        albumSection("Singles & EPs", content.singlesAndEPs, sort: .singlesAndEPs, showsArtist: false)
    }

    @ViewBuilder
    private func albumSection(_ title: String, _ albums: [Album], sort: ArtistSorts.Section, showsArtist: Bool) -> some View {
        if !albums.isEmpty {
            section(title) {
                AlbumSortMenu(key: sorts[sort]) { key in
                    var updated = sorts
                    updated[sort] = key
                    sortsData = updated.encoded()
                }
            } content: {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 22)], spacing: 26) {
                    ForEach(Array(albums.enumerated()), id: \.element.id) { i, album in
                        AlbumTile(album: album, showsArtist: showsArtist).keyboardGridItem(i)
                    }
                }
                .keyboardGrid(count: albums.count, layout: .adaptive(minimum: 160, spacing: 22, inset: 0), id: { albums[$0].id })
            }
        }
    }

    private var sorts: ArtistSorts { ArtistSorts.decode(sortsData, customFields: pages.customFields) }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        section(title, accessory: { EmptyView() }, content: content)
    }

    private func section<Accessory: View, Content: View>(_ title: String, @ViewBuilder accessory: () -> Accessory,
                                                         @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(palette?.primary.color ?? Color.primary)
                Spacer()
                accessory()
            }
            content()
        }
    }

    // MARK: Loading

    /// The page's area and the album its colours come from, so its colours fade out as it leaves.
    private func registerPage(_ artist: Artist) {
        hero.setPage(pageProbe, for: .artist(artist.id), colours: tint?.albumID ?? content?.featuredAlbumID)
    }

    /// What the artist's sections depend on: the artist, plays, and the chosen sort orders.
    private func contentKey(_ artist: Artist) -> String {
        "\(artist.id)-\(history.version)-\(sortsData?.hashValue ?? 0)"
    }

    /// The artist's own albums, songs and stats, synchronously: a few hundred tracks at most.
    private func buildLocalContent(_ artist: Artist) {
        content = ArtistPageContent.local(artist: artist, snapshot: library.snapshot, history: history.stats, sorts: sorts)
    }

    private func loadAppearsOn(_ artist: Artist) async {
        let snapshot = library.snapshot
        let stats = history.stats
        let sort = sorts.appearsOn
        let found = await Task.detached(priority: .userInitiated) {
            ArtistPageContent.appearsOn(artist: artist, snapshot: snapshot, history: stats, sort: sort)
        }.value
        guard !Task.isCancelled else { return }
        appearsOn = found
    }

    private func loadInfo(_ artist: Artist) async {
        guard let infoProvider else { infoLoading = false; return }
        infoLoading = true
        let token = infoOnline ? Keychain.string(for: ArtistInfoSettings.tokenAccount) : nil
        let found = await infoProvider.info(name: artist.name, key: artist.id, token: token, online: infoOnline)
        guard !Task.isCancelled else { return }
        info = found
        infoLoading = false
        // A first lookup may have just downloaded their photo: every view of this artist picks it up.
        if found?.photo != nil { artistImages?.refresh(artist.id) }
    }
}

/// "Appears On" while it's being worked out: its heading and a row of shimmering tiles.
private struct LoadingAlbumSection: View {
    let title: String
    let palette: ArtworkPalette?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title2.bold())
                .foregroundStyle(palette?.primary.color ?? Color.primary)
            HStack(spacing: 22) {
                ForEach(0..<4, id: \.self) { _ in ShimmerBlock(width: 160, height: 160, cornerRadius: 10) }
            }
        }
    }
}

/// About while Discogs is being asked: its heading and a few shimmering lines of text.
private struct LoadingAboutSection: View {
    let palette: ArtworkPalette?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("About")
                .font(.title2.bold())
                .foregroundStyle(palette?.primary.color ?? Color.primary)
            ForEach([1.0, 0.96, 0.9, 0.55], id: \.self) { fraction in
                GeometryReader { proxy in ShimmerBlock(width: min(720, proxy.size.width) * fraction, height: 12) }
                    .frame(height: 12)
            }
        }
    }
}

/// An album section's sort order: the fields a smart filter can sort albums by, your custom fields, and
/// Random, plus the direction. Shared by every artist page (see `ArtistSorts`).
private struct AlbumSortMenu: View {
    let key: SortKey
    let set: (SortKey) -> Void
    @Environment(PageStore.self) private var pages

    var body: some View {
        Menu {
            Picker("Sort By", selection: Binding(get: { key.field }, set: { set(ArtistSorts.key(for: $0)) })) {
                ForEach(ArtistSorts.fields, id: \.self) { Text(ArtistSorts.title(.field($0))).tag(SortField.field($0)) }
                if !pages.customFields.isEmpty {
                    Divider()
                    ForEach(pages.customFields) { field in Text(field.name).tag(SortField.custom(field)) }
                }
                Divider()
                Text("Random").tag(SortField.random)
            }
            .pickerStyle(.inline)
            if let labels = SortKeysEditor.orderLabels(key.field) {
                Picker("Order", selection: Binding(get: { key.ascending }, set: { set(SortKey(field: key.field, ascending: $0)) })) {
                    Text(labels.descending).tag(false)
                    Text(labels.ascending).tag(true)
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label(ArtistSorts.title(key.field), systemImage: "arrow.up.arrow.down")
                .font(.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort")
    }
}

/// About, at the end of the artist page: the full bio, members, groups, aliases and links from Discogs,
/// with the credit Discogs asks for and "Wrong artist?".
private struct ArtistAboutSection: View {
    let artist: Artist
    let info: ArtistInfo
    let palette: ArtworkPalette?
    let chose: (ArtistInfo?) -> Void
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigator.self) private var navigator
    @State private var choosing = false

    private var secondary: AnyShapeStyle {
        palette.map { AnyShapeStyle($0.secondary.color) } ?? AnyShapeStyle(.secondary)
    }

    var body: some View {
        let discogs = info.artist
        VStack(alignment: .leading, spacing: 14) {
            Text("About")
                .font(.title2.bold())
                .foregroundStyle(palette?.primary.color ?? Color.primary)
            if let bio = discogs.plainProfile, !bio.isEmpty {
                Text(bio)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: 720, alignment: .leading)
            }
            facts("Members", discogs.members)
            facts("Groups", discogs.groups)
            facts("Aliases", discogs.aliases)
            if let urls = discogs.urls?.compactMap(URL.init(string:)), !urls.isEmpty {
                row("Links") {
                    FlowLayout(spacing: 12) {
                        ForEach(urls, id: \.self) { url in
                            Link(url.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString,
                                 destination: url)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                if let link = discogs.uri.flatMap(URL.init(string:)) {
                    Link("Data provided by Discogs", destination: link)
                } else {
                    Text("Data provided by Discogs")
                }
                Text("·")
                Button("Wrong artist?") { choosing = true }
                    .linkButtonStyle()
            }
            .font(.caption)
            .foregroundStyle(secondary)
        }
        .sheet(isPresented: $choosing) {
            DiscogsArtistPicker(artist: artist) { picked in
                chose(picked)
                choosing = false
            }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(secondary)
                .frame(width: 70, alignment: .leading)
            content().font(.callout)
        }
    }

    /// People and groups; the ones that are artists in the library open their page.
    @ViewBuilder
    private func facts(_ title: String, _ references: [DiscogsArtist.Reference]?) -> some View {
        if let references, !references.isEmpty {
            row(title) {
                FlowLayout(spacing: 12) {
                    ForEach(references, id: \.id) { reference in
                        let name = ArtistMatcher.baseName(reference.name)
                        if library.snapshot.artistsByID[name.lowercased()] != nil {
                            Button(name) { navigator.openArtist(name.lowercased()) }
                                .linkButtonStyle()
                        } else {
                            Text(name).foregroundStyle(reference.active == false ? secondary : AnyShapeStyle(.primary))
                        }
                    }
                }
            }
        }
    }
}

/// With lookups on but no match found: a quiet way to pick the artist on Discogs by hand.
private struct DiscogsFindLink: View {
    let artist: Artist
    let chose: (ArtistInfo?) -> Void
    @State private var choosing = false

    var body: some View {
        Button("Find “\(artist.name)” on Discogs…") { choosing = true }
            .linkButtonStyle()
            .font(.caption)
            .sheet(isPresented: $choosing) {
                DiscogsArtistPicker(artist: artist) { picked in
                    chose(picked)
                    choosing = false
                }
            }
    }
}

/// Lays children out left to right, wrapping onto new lines, for name and link lists.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += line + lineSpacing
                x = 0
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += line + lineSpacing
                x = bounds.minX
                line = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}

/// "Wrong artist?": Discogs' search results for the name, to pick the right one by hand.
private struct DiscogsArtistPicker: View {
    let artist: Artist
    let picked: (ArtistInfo?) -> Void
    @Environment(\.artistInfoProvider) private var infoProvider
    @Environment(\.dismiss) private var dismiss
    @State private var results: [DiscogsSearchResult]?
    @State private var loadingID: Int?
    /// Why there's nothing to show, or why the last pick didn't load.
    @State private var problem: String?
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose “\(artist.name)” on Discogs").font(.headline)
            Group {
                if results == nil, let problem {
                    VStack(spacing: 10) {
                        Text(problem).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Try Again") { attempt += 1 }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let results {
                    if results.isEmpty {
                        Text("Discogs found no artists by that name.").foregroundStyle(.secondary)
                    } else {
                        List(results) { result in
                            Button { choose(result) } label: {
                                HStack(spacing: 10) {
                                    AsyncImage(url: result.thumb.flatMap(URL.init(string:))) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Color.secondary.opacity(0.15)
                                    }
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                    Text(result.title)
                                    Spacer()
                                    if loadingID == result.id { ProgressView().controlSize(.small) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(height: 300)
            HStack {
                // A pick that couldn't be loaded: the list stays to try again.
                if results != nil, let problem {
                    Text(problem).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .sheetSize(width: 420)
        .task(id: attempt) {
            results = nil
            problem = nil
            guard let infoProvider, let token = Keychain.string(for: ArtistInfoSettings.tokenAccount), !token.isEmpty else {
                problem = "Add your Discogs token in Settings to search Discogs."
                return
            }
            results = await infoProvider.candidates(name: artist.name, token: token)
            if results == nil { problem = "Couldn’t reach Discogs. Check your connection and try again." }
        }
    }

    private func choose(_ result: DiscogsSearchResult) {
        guard let infoProvider, let token = Keychain.string(for: ArtistInfoSettings.tokenAccount) else { return }
        loadingID = result.id
        problem = nil
        Task {
            guard let info = await infoProvider.choose(id: result.id, key: artist.id, token: token) else {
                loadingID = nil
                problem = "Couldn’t load that artist from Discogs. Try again."
                return
            }
            picked(info)
        }
    }
}
