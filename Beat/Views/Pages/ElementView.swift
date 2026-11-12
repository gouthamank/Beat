import SwiftUI

struct ElementRoute: Hashable {
    let pageID: UUID
    let elementID: UUID
}

/// One element on a page: a header plus its smart filter's result, laid out by its appearance.
struct ElementView: View {
    let element: PageElement
    let pageID: UUID
    let result: FilterResult?
    /// Edit Page mode: always shows the header, with inline controls.
    let editing: Bool
    let delete: () -> Void
    /// The editor's live preview: renders as on the page, but nothing in it can change or leave the page.
    var isPreview = false
    @Environment(PlaybackQueue.self) private var queue
    @Environment(PageStore.self) private var pages
    @Environment(AppNavigator.self) private var navigator

    private var look: ElementAppearance { element.appearance }

    var body: some View {
        let isEmpty = result?.count == 0
        // A headerless element with nothing to show would be an unexplained gap, so it disappears instead.
        if editing || look.showHeader || !isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                if editing || look.showHeader {
                    if isPreview {
                        header
                    } else {
                        header.contextMenu { ElementMenu(element: element, pageID: pageID, delete: delete) }
                    }
                }
                if let result {
                    if result.count == 0 {
                        Text("No matches").font(.callout).foregroundStyle(.secondary).padding(.horizontal, 24)
                    } else {
                        content(result)
                    }
                } else {
                    placeholder
                }
            }
            .padding(.vertical, look.spacing.elementPadding)
            // The element's own menu on its empty space too, so it stays editable with the header hidden.
            // Items keep their own menus; they sit above this.
            .background {
                if !isPreview {
                    Color.clear
                        .contentShape(Rectangle())
                        .contextMenu { ElementMenu(element: element, pageID: pageID, delete: delete) }
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if isPreview {
                title
            } else {
                Button { navigator.push(.element(ElementRoute(pageID: pageID, elementID: element.id))) } label: { title }
                    .buttonStyle(.plain)
                    .help("See All")
            }

            if editing, !look.showHeader {
                Text("Header hidden").font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if editing, !isPreview {
                editControls
            } else if look.showPlayButtons, let tracks = result?.tracks, !tracks.isEmpty {
                BeatGlassContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        Button { queue.play(tracks) } label: { Image(systemName: "play.fill").frame(width: 16) }
                            .help("Play")
                        Button { queue.play(tracks, shuffled: true) } label: { Image(systemName: "shuffle").frame(width: 16) }
                            .help("Shuffle")
                    }
                    .beatGlassButtonStyle()
                }
                // Shown in the editor's preview so the header looks right, but not live there.
                .allowsHitTesting(!isPreview)
            }
        }
        .padding(.horizontal, 24)
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(element.filter.name.isEmpty ? "Untitled" : element.filter.name)
                .font(.title2.bold())
            Image(systemName: "chevron.right")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private var editControls: some View {
        let elements = pages.node(pageID)?.page?.elements ?? []
        let index = elements.firstIndex { $0.id == element.id } ?? 0
        return HStack(spacing: 12) {
            Button { pages.moveElement(element.id, on: pageID, by: -1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0).help("Move Up")
            Button { pages.moveElement(element.id, on: pageID, by: 1) } label: { Image(systemName: "chevron.down") }
                .disabled(index >= elements.count - 1).help("Move Down")
            Button { navigator.edit(element, on: pageID) } label: { Image(systemName: "slider.horizontal.3") }
                .help("Edit Element")
            Button { pages.duplicateElement(element.id, on: pageID) } label: { Image(systemName: "plus.square.on.square") }
                .help("Duplicate")
            Button(action: delete) { Image(systemName: "trash") }
                .help("Delete Element")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func content(_ result: FilterResult) -> some View {
        let gap = look.spacing.itemGap
        let width = look.size.tileWidth(for: result.kind)
        let footer = look.showFooter
        // Footers under tiles need a little extra room between rows; art alone doesn't.
        let tileRowGap = footer ? gap + 6 : gap
        switch (result.kind, look.layout) {
        case (.songs, .list):
            let tracks = result.tracks
            ColumnList(count: tracks.count, rows: look.rows, columns: look.columns, fill: look.effectiveFill, spacing: gap) { i in
                SongCell(track: tracks[i], context: tracks, index: i)
            }
        case (.songs, _):
            let tracks = result.tracks
            Shelf(count: tracks.count, rows: look.rows, fill: look.effectiveFill, spacing: gap, rowSpacing: 4) { i in
                SongCell(track: tracks[i], context: tracks, index: i).frame(width: width)
            }
        case (.albums, .list):
            let albums = result.albums
            ColumnList(count: albums.count, rows: look.rows, columns: look.columns, fill: look.effectiveFill, spacing: gap) { AlbumListCell(album: albums[$0]) }
        case (.artists, .list):
            let artists = result.artists
            ColumnList(count: artists.count, rows: look.rows, columns: look.columns, fill: look.effectiveFill, spacing: gap) { ArtistListCell(artist: artists[$0]) }
        case (.genres, .list):
            let genres = result.genres
            ColumnList(count: genres.count, rows: look.rows, columns: look.columns, fill: look.effectiveFill, spacing: gap) { GenreListCell(genre: genres[$0]) }
        case (.albums, .coverFlow):
            CoverFlowElement(albums: result.albums, side: CoverFlowGeometry.side(for: look.size),
                             spread: CoverFlowGeometry.spread(for: look.spacing))
        case (.albums, .timeline):
            let albums = result.albums
            YearTimelineElement(count: albums.count, year: { albums[$0].year }, newestFirst: look.timelineOrder == .newestFirst,
                                rows: look.rows, maxColumns: look.timelineMaxColumns, fill: look.effectiveFill,
                                tileWidth: width, spacing: gap,
                                rowSpacing: tileRowGap) { AlbumTile(album: albums[$0], showsFooter: footer) }
        case (.albums, .grid):
            let albums = result.albums
            TileGrid(count: albums.count, rows: look.rows, fill: look.effectiveFill, minimum: width, spacing: gap, rowSpacing: tileRowGap) { i in
                AlbumTile(album: albums[i], showsFooter: footer)
            }
        case (.albums, _):
            let albums = result.albums
            Shelf(count: albums.count, rows: look.rows, fill: look.effectiveFill, spacing: gap, rowSpacing: tileRowGap) { i in
                AlbumTile(album: albums[i], showsFooter: footer)
                    .frame(width: width)
            }
        case (.artists, .grid):
            let artists = result.artists
            TileGrid(count: artists.count, rows: look.rows, fill: look.effectiveFill, minimum: width, spacing: gap, rowSpacing: tileRowGap) {
                ArtistTile(artist: artists[$0], showsFooter: footer)
            }
        case (.artists, _):
            let artists = result.artists
            Shelf(count: artists.count, rows: look.rows, fill: look.effectiveFill, spacing: gap, rowSpacing: tileRowGap) {
                ArtistTile(artist: artists[$0], showsFooter: footer).frame(width: width)
            }
        case (.genres, .grid):
            let genres = result.genres
            TileGrid(count: genres.count, rows: look.rows, fill: look.effectiveFill, minimum: width, spacing: gap, rowSpacing: gap) {
                GenreTile(genre: genres[$0], showsFooter: footer)
            }
        case (.genres, _):
            let genres = result.genres
            Shelf(count: genres.count, rows: look.rows, fill: look.effectiveFill, spacing: gap, rowSpacing: gap) {
                GenreTile(genre: genres[$0], showsFooter: footer).frame(width: width)
            }
        }
    }
}

// MARK: Loading placeholder

extension ElementView {
    /// The element's own layout at its final size while its filter runs, with empty cover shapes for items:
    /// a spinner was one line tall, so each element jumped open (pushing the rest down) as its results came in.
    /// Text keeps its space, invisibly. Layouts that grow to fit everything reserve one row.
    @ViewBuilder
    var placeholder: some View {
        let kind = element.filter.output
        let gap = look.spacing.itemGap
        let width = look.size.tileWidth(for: kind)
        let footer = look.showFooter
        let tileRowGap = footer ? gap + 6 : gap
        let allRows = look.rows == ElementAppearance.allRows
        // Enough to fill the rows across any window; layouts that grow to fit get about a row.
        let count = allRows ? (look.layout == .list ? look.columns : 6) : max(1, look.rows) * (look.layout == .list ? look.columns : 12)
        Group {
            switch (kind, look.layout) {
            case (_, .list):
                ColumnList(count: count, rows: look.rows, columns: look.columns, fill: look.effectiveFill, spacing: gap) { _ in
                    PlaceholderRow()
                }
            case (.songs, _):
                Shelf(count: count, rows: look.rows, fill: look.effectiveFill, spacing: gap, rowSpacing: 4) { _ in
                    PlaceholderRow().frame(width: width)
                }
            case (.albums, .coverFlow):
                CoverFlowPlaceholder(side: CoverFlowGeometry.side(for: look.size), spread: CoverFlowGeometry.spread(for: look.spacing))
            case (.albums, .timeline):
                YearTimelineElement(count: count, year: { _ in 0 }, newestFirst: false, rows: look.rows,
                                    maxColumns: look.timelineMaxColumns, fill: look.effectiveFill, tileWidth: width,
                                    spacing: gap, rowSpacing: tileRowGap, hidesYears: true) { _ in
                    PlaceholderTile(kind: .albums, footer: footer)
                }
            case (_, .grid):
                TileGrid(count: count, rows: look.rows, fill: look.effectiveFill, minimum: width, spacing: gap,
                         rowSpacing: kind == .genres ? gap : tileRowGap) { _ in
                    PlaceholderTile(kind: kind, footer: footer)
                }
            default:
                Shelf(count: count, rows: look.rows, fill: look.effectiveFill, spacing: gap,
                      rowSpacing: kind == .genres ? gap : tileRowGap) { _ in
                    PlaceholderTile(kind: kind, footer: footer).frame(width: width)
                }
            }
        }
        .disabled(true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// An empty cover in the faint fill a cover shows before its art loads, shaped like the tile it stands in for.
/// Footer text keeps its space but isn't drawn.
private struct PlaceholderTile: View {
    let kind: ResultKind
    let footer: Bool

    var body: some View {
        switch kind {
        case .genres:
            // Genre names sit on the art, so the tile is the art alone.
            cover(cornerRadius: 14)
        case .artists:
            VStack(spacing: 8) {
                cover(cornerRadius: 10)
                if footer { lines(.callout.weight(.medium), .caption) }
            }
        default:
            VStack(alignment: .leading, spacing: 6) {
                cover(cornerRadius: 10)
                if footer { lines(.callout.weight(.medium), .caption) }
            }
        }
    }

    private func cover(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.quaternary).aspectRatio(1, contentMode: .fit)
    }

    private func lines(_ first: Font, _ second: Font) -> some View {
        Group {
            Text(verbatim: " ").font(first)
            Text(verbatim: " ").font(second)
        }
    }
}

/// A list row's shape (`ListCellContent`, `SongCell`): a small empty cover, two lines' space.
private struct PlaceholderRow: View {
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.quaternary).frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: " ").font(.callout)
                Text(verbatim: " ").font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
    }
}

/// Cover Flow's stage with empty covers in place, and its caption's space.
private struct CoverFlowPlaceholder: View {
    let side: CGFloat
    let spread: CGFloat

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                ForEach(-2...2, id: \.self) { d in
                    let place = CoverFlowGeometry.place(distance: d, side: side, spread: spread)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.quaternary)
                        .frame(width: side, height: side)
                        .scaleEffect(place.scale)
                        .rotation3DEffect(.degrees(place.rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                        .offset(x: place.x)
                        .zIndex(place.zIndex)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: CoverFlowGeometry.stageHeight(side: side))
            VStack(spacing: 2) {
                Text(verbatim: " ").font(.callout.weight(.semibold))
                Text(verbatim: " ").font(.caption)
            }
        }
        .padding(.vertical, 6)
    }
}

extension ElementAppearance.Size {
    func tileWidth(for kind: ResultKind) -> CGFloat {
        let widths: (CGFloat, CGFloat, CGFloat) = switch kind {
        case .albums: (132, 168, 210)
        case .artists: (110, 140, 176)
        case .genres: (150, 180, 220)
        case .songs: (260, 300, 360)
        }
        return switch self {
        case .small: widths.0
        case .medium: widths.1
        case .large: widths.2
        }
    }
}

extension ElementAppearance.Spacing {
    var itemGap: CGFloat {
        switch self {
        case .compact: 10
        case .regular: 18
        case .roomy: 28
        }
    }

    var elementPadding: CGFloat {
        switch self {
        case .compact: 0
        case .regular: 6
        case .roomy: 14
        }
    }
}

// MARK: Building blocks

/// Items in `rows` rows that scroll sideways together, like Apple Music's shelves. Across (the default) runs
/// each row all the way along; Down fills column by column.
private struct Shelf<Cell: View>: View {
    let count: Int
    let rows: Int
    let fill: ElementAppearance.Fill
    let spacing: CGFloat
    let rowSpacing: CGFloat
    @ViewBuilder let cell: (Int) -> Cell
    @Environment(\.elementPreview) private var previewing

    var body: some View {
        let rows = max(1, min(rows, count))
        let columns = ElementPaging.columns(count: count, rows: rows, fill: fill)
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: spacing) {
                ForEach(columns.indices, id: \.self) { column in
                    VStack(alignment: .leading, spacing: rowSpacing) {
                        ForEach(columns[column], id: \.self) {
                            cell($0).allowsHitTesting(!previewing).keyboardGridItem($0)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
        }
        .keyboardGrid(count: count, layout: .order(.slots(columns)))
    }
}

/// Columns of items that scroll sideways and snap to a column, for capped grids and lists: rows × columns is
/// one screenful, and the rest continue to the right. `columns` comes from `ElementPaging.columns`.
private struct PagedColumns<Cell: View>: View {
    let count: Int
    let columns: [[Int]]
    let columnWidth: CGFloat
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    @ViewBuilder let cell: (Int) -> Cell
    @Environment(\.elementPreview) private var previewing

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: columnSpacing) {
                ForEach(columns.indices, id: \.self) { column in
                    VStack(spacing: rowSpacing) {
                        ForEach(columns[column], id: \.self) {
                            cell($0).allowsHitTesting(!previewing).keyboardGridItem($0)
                        }
                    }
                    .frame(width: columnWidth, alignment: .top)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .keyboardGrid(count: count, layout: .order(.slots(columns)))
    }
}

/// Fixed columns that share the row evenly, each a `VStack` of its items: grids and lists that fit, filled down.
private struct FittedColumns<Cell: View>: View {
    let count: Int
    let columns: [[Int]]
    /// How many columns the row is divided into, even when fewer are used.
    let columnCount: Int
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    @ViewBuilder let cell: (Int) -> Cell
    @Environment(\.elementPreview) private var previewing

    var body: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            ForEach(0..<max(columnCount, columns.count), id: \.self) { column in
                if column < columns.count {
                    VStack(spacing: rowSpacing) {
                        ForEach(columns[column], id: \.self) {
                            cell($0).allowsHitTesting(!previewing).keyboardGridItem($0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                } else {
                    // Keep column widths fixed when the last columns are empty.
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                }
            }
        }
        .padding(.horizontal, 24)
        .keyboardGrid(count: count, layout: .order(.slots(columns)))
    }
}

/// An adaptive grid; the column count comes from the measured width. With a row limit and more items
/// than fit, it scrolls sideways instead (`PagedColumns`); with Rows set to All, every item shows.
private struct TileGrid<Cell: View>: View {
    let count: Int
    let rows: Int
    let fill: ElementAppearance.Fill
    let minimum: CGFloat
    let spacing: CGFloat
    let rowSpacing: CGFloat
    @ViewBuilder let cell: (Int) -> Cell
    @State private var width: CGFloat = 0
    @Environment(\.elementPreview) private var previewing

    var body: some View {
        let columns = GridNavigation.adaptiveColumns(width: width, minimum: minimum, spacing: spacing, inset: 24)
        Group {
            if rows != ElementAppearance.allRows, ElementPaging.isCapped(count: count, rows: rows, columns: columns) {
                // Tiles sized so a screenful holds exactly `columns` of them.
                let tile = max(minimum, (width - 48 - spacing * CGFloat(columns - 1)) / CGFloat(columns))
                PagedColumns(count: count, columns: ElementPaging.columns(count: count, rows: rows, fill: fill),
                             columnWidth: tile, columnSpacing: spacing, rowSpacing: rowSpacing, cell: cell)
            } else if fill == .down, width > 0 {
                FittedColumns(count: count,
                              columns: ElementPaging.columns(count: count, rows: ElementPaging.rowsNeeded(count: count, columns: columns),
                                                             fill: .down),
                              columnCount: columns, columnSpacing: spacing, rowSpacing: rowSpacing, cell: cell)
            } else {
                // The measured column count, each column flexible: tiles share the row evenly and start under
                // the heading. An adaptive grid capped each tile's growth and centred what was left, so a
                // short row drifted right and its tiles jumped in size when the window narrowed by a few points.
                // Before the first measurement the adaptive grid stands in, so nothing renders one column wide.
                let gridColumns = width > 0
                    ? Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)
                    : [GridItem(.adaptive(minimum: minimum, maximum: minimum + 60), spacing: spacing)]
                LazyVGrid(columns: gridColumns, spacing: rowSpacing) {
                    ForEach(0..<count, id: \.self) { cell($0).allowsHitTesting(!previewing).keyboardGridItem($0) }
                }
                .padding(.horizontal, 24)
                .keyboardGrid(count: count, layout: .order(.rows(columns: columns)))
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

/// Items in equal-width columns, across each row (the default) or down each column. With more than
/// rows × columns it scrolls sideways a column at a time; with Rows set to All it grows to fit everything.
private struct ColumnList<Cell: View>: View {
    let count: Int
    let rows: Int
    let columns: Int
    let fill: ElementAppearance.Fill
    let spacing: CGFloat
    @ViewBuilder let cell: (Int) -> Cell
    @State private var width: CGFloat = 0

    var body: some View {
        let perColumn = rows == ElementAppearance.allRows ? max(1, ElementPaging.rowsNeeded(count: count, columns: columns)) : rows
        let columnGap = spacing + 6
        let rowGap = max(2, spacing / 6)
        let capped = ElementPaging.isCapped(count: count, rows: perColumn, columns: columns)
        // Across in a list that fits reads across its columns: just enough rows to fill them.
        let laidOut = ElementPaging.columns(count: count, rows: fill == .across && !capped
                                                ? ElementPaging.rowsNeeded(count: count, columns: columns) : perColumn,
                                            fill: fill)
        Group {
            if capped {
                let columnWidth = max(160, (width - 48 - columnGap * CGFloat(columns - 1)) / CGFloat(columns))
                PagedColumns(count: count, columns: laidOut, columnWidth: columnWidth, columnSpacing: columnGap,
                             rowSpacing: rowGap, cell: cell)
            } else {
                FittedColumns(count: count, columns: laidOut, columnCount: columns, columnSpacing: columnGap,
                              rowSpacing: rowGap, cell: cell)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

private struct AlbumListCell: View {
    let album: Album
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigator.self) private var navigator
    @Environment(HeroTransition.self) private var hero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.albumNavigationDisabled) private var navigationDisabled
    @Environment(\.gridItem) private var gridItem
    @State private var probe = FrameProbe()
    @State private var armed = false

    var body: some View {
        // A tap gesture, as on album tiles.
        ListCellContent(albumID: album.id, title: album.title, subtitle: album.artist, probe: probe,
                        hidesArt: hero.isReturning(to: album.id),
                        keepsProbe: armed || gridItem.highlighted || hero.lastOpened == .album(album.id),
                        highlighted: gridItem.highlighted)
            .onTapGesture(perform: open)
            .onChange(of: gridItem.activation) { _, serial in if serial != nil { open() } }
            .accessibilityAddTraits(.isButton)
        .contextMenu { TrackContextMenu(tracks: library.snapshot.tracks(of: album)) }
        .onHover { if $0, !navigationDisabled { navigator.coverTint.prefetch(.album(album.id)) } }
        .task(id: album.id) { hero.registerTile(probe, for: album.id, cornerRadius: 5) }
    }

    private func open() {
        guard !navigationDisabled else { return }
        armed = true
        navigator.openWhenReady(.album(album.id)) {
            hero.open(album.id, from: probe, cornerRadius: 5, navigator: navigator, reduceMotion: reduceMotion)
        }
    }
}

private struct ArtistListCell: View {
    let artist: Artist
    @Environment(AppNavigator.self) private var navigator
    @Environment(HeroTransition.self) private var hero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.albumNavigationDisabled) private var navigationDisabled
    @Environment(\.gridItem) private var gridItem
    @State private var probe = FrameProbe()
    @State private var armed = false

    var body: some View {
        // A tap gesture, as on album tiles.
        ListCellContent(albumID: nil, title: artist.name,
                        subtitle: artist.albumIDs.count.counted("album"),
                        probe: probe, hidesArt: hero.isReturning(to: .artist(artist.id)),
                        artistAlbumIDs: artist.albumIDsNewestFirst, artistID: artist.id,
                        keepsProbe: armed || gridItem.highlighted || hero.lastOpened == .artist(artist.id),
                        highlighted: gridItem.highlighted)
            .onTapGesture(perform: open)
            .onChange(of: gridItem.activation) { _, serial in if serial != nil { open() } }
            .accessibilityAddTraits(.isButton)
        .onHover { if $0, !navigationDisabled { navigator.coverTint.prefetch(.artist(artist.id)) } }
        .task(id: artist.id) { hero.registerTile(probe, for: .artist(artist.id), cornerRadius: 5) }
    }

    private func open() {
        guard !navigationDisabled else { return }
        armed = true
        navigator.openWhenReady(.artist(artist.id)) {
            hero.open(.artist(artist.id), from: probe, cornerRadius: 5, navigator: navigator, reduceMotion: reduceMotion)
        }
    }
}

private struct GenreListCell: View {
    let genre: Genre
    @Environment(AppNavigator.self) private var navigator
    @Environment(\.albumNavigationDisabled) private var navigationDisabled
    @Environment(\.gridItem) private var gridItem

    var body: some View {
        Button { if !navigationDisabled { navigator.openGenre(genre.id) } } label: {
            ListCellContent(albumID: genre.albumIDs.first, title: genre.name, subtitle: genre.trackCount.counted("song"),
                            highlighted: gridItem.highlighted)
        }
        .buttonStyle(.plain)
        // The list is the Tab stop, not each row.
        .focusable(false)
        .onChange(of: gridItem.activation) { _, serial in
            if serial != nil, !navigationDisabled { navigator.openGenre(genre.id) }
        }
    }
}

/// Art, title and subtitle laid out like `SongCell`, so mixed lists line up.
private struct ListCellContent: View {
    let albumID: PersistentID?
    let title: String
    let subtitle: String
    var round = false
    /// Measures the art, for the album zoom.
    var probe: FrameProbe?
    /// While the cover flies back into this row.
    var hidesArt = false
    /// An artist row: their photo or cover mosaic instead of a single cover.
    var artistAlbumIDs: [PersistentID]?
    var artistID: String?
    /// Clicked or last opened: keep the probe without hover (see HeroTransition.lastOpened).
    var keepsProbe = false
    /// The keyboard highlight (see KeyboardGrid).
    var highlighted = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let artistAlbumIDs {
                    ArtistArtwork(albumIDs: artistAlbumIDs, artistID: artistID, cornerRadius: 5)
                } else {
                    ArtworkView(albumID: albumID, cornerRadius: round ? 0 : 5)
                }
            }
                .frame(width: 42, height: 42)
                .background { if let probe, hovering || keepsProbe { Color.clear.frameProbe(probe) } }
                .clipShape(round ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 5)))
                .opacity(hidesArt ? 0 : 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).lineLimit(1)
                Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .background(.primary.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .keyboardHighlight(highlighted, cornerRadius: 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

struct SongCell: View {
    let track: Track
    /// The list this song is played from, so playback continues through it.
    let context: [Track]
    let index: Int
    @Environment(PlaybackQueue.self) private var queue
    @Environment(\.gridItem) private var gridItem
    @Environment(\.playbackAccent) private var playbackAccent
    @State private var hovering = false

    var body: some View {
        let isCurrent = queue.current?.id == track.id
        HStack(spacing: 10) {
            ArtworkView(albumID: track.albumID, cornerRadius: 5)
                .frame(width: 42, height: 42)
                .overlay {
                    if hovering || isCurrent {
                        RoundedRectangle(cornerRadius: 5).fill(.black.opacity(0.45))
                        if isCurrent {
                            PlayingIndicator(isAnimating: queue.isPlaying, color: .white)
                        } else {
                            Image(systemName: "play.fill").foregroundStyle(.white)
                        }
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.callout.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                Text("\(track.displayArtist) · \(track.album)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .background(isCurrent ? AnyShapeStyle(playbackAccent.opacity(0.16)) : AnyShapeStyle(.primary.opacity(hovering ? 0.06 : 0)),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .keyboardHighlight(gridItem.highlighted, cornerRadius: 4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // The whole row is the play button the hover icon on the art shows: a click plays the song, or on
        // the playing song pauses and resumes. A double-click just plays, rather than playing on the first
        // click and pausing on the second.
        .gesture(
            TapGesture(count: 2).onEnded { queue.play(context, startAt: index) }
                .exclusively(before: TapGesture().onEnded {
                    isCurrent ? queue.togglePlayPause() : queue.play(context, startAt: index)
                })
        )
        .help(isCurrent && queue.isPlaying ? "Pause" : "Play")
        // Space or Return on the highlighted song plays it, like a double-click.
        .onChange(of: gridItem.activation) { _, serial in if serial != nil { queue.play(context, startAt: index) } }
        .contextMenu { TrackContextMenu(tracks: [track]) }
    }
}
