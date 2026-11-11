import AppKit
import SwiftUI

// Library ▸ Songs on an AppKit table. A SwiftUI lazy stack of ~3k variable-height album blocks spent
// most of its time in layout and hover hit-testing; NSTableView reuses a screenful of rows instead.

/// Library ▸ Songs flattened into table rows: a floating header per album artist, then each album's
/// songs between a top spacer and a bottom spacer tall enough for the album's cover block.
struct AlbumSongsLayout {
    struct Metrics: Equatable {
        var song: CGFloat
        var songWithArtist: CGFloat
        var artist: CGFloat
        /// Space above and below each album's block.
        var padding: CGFloat = 14
        /// The album title under the square cover.
        var coverTitle: CGFloat
        /// The year line under that.
        var year: CGFloat
    }

    enum Row: Equatable {
        case artist(section: Int)
        case albumTop(album: Int)
        /// `play` is the song's index in the page's play order.
        case song(album: Int, track: Int, play: Int)
        case albumBottom(album: Int)
    }

    struct AlbumSpan: Equatable {
        let section: Int
        let group: Int
        /// The album's top and bottom spacer rows.
        let top: Int
        let bottom: Int
        let songsHeight: CGFloat
        let hasYear: Bool
        let isFirstInSection: Bool
    }

    let metrics: Metrics
    private(set) var rows: [Row] = []
    private(set) var albums: [AlbumSpan] = []
    private(set) var rowOfTrack: [PersistentID: Int] = [:]
    private var songHeights: [CGFloat] = []

    init(sections: [ArtistSection], metrics: Metrics) {
        self.metrics = metrics
        var play = 0
        for (s, section) in sections.enumerated() {
            rows.append(.artist(section: s))
            songHeights.append(0)
            for (g, group) in section.groups.enumerated() {
                let a = albums.count
                let top = rows.count
                rows.append(.albumTop(album: a))
                songHeights.append(0)
                var height: CGFloat = 0
                for (t, track) in group.tracks.enumerated() {
                    let h = track.displayArtist != group.album.artist ? metrics.songWithArtist : metrics.song
                    rowOfTrack[track.id] = rows.count
                    rows.append(.song(album: a, track: t, play: play))
                    songHeights.append(h)
                    height += h
                    play += 1
                }
                rows.append(.albumBottom(album: a))
                songHeights.append(0)
                albums.append(AlbumSpan(section: s, group: g, top: top, bottom: rows.count - 1, songsHeight: height,
                                        hasYear: group.album.year > 0, isFirstInSection: g == 0))
            }
        }
    }

    /// The cover, its title and (when known) its year.
    func coverHeight(album a: Int, artWidth: CGFloat) -> CGFloat {
        artWidth + metrics.coverTitle + (albums[a].hasYear ? metrics.year : 0)
    }

    func height(of row: Int, artWidth: CGFloat) -> CGFloat {
        switch rows[row] {
        case .artist: metrics.artist
        case .albumTop: metrics.padding
        case .song: songHeights[row]
        case .albumBottom(let a):
            max(metrics.padding, coverHeight(album: a, artWidth: artWidth) + metrics.padding - albums[a].songsHeight)
        }
    }

    func isSong(_ row: Int) -> Bool {
        if case .song = rows[row] { true } else { false }
    }

    /// Albums whose rows overlap `first...last`, by binary search (albums are in row order).
    func albumRange(overlapping first: Int, _ last: Int) -> Range<Int> {
        var lo = 0, hi = albums.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if albums[mid].bottom < first { lo = mid + 1 } else { hi = mid }
        }
        var end = lo
        while end < albums.count, albums[end].top <= last { end += 1 }
        return lo..<end
    }
}

/// The table itself, inside an NSScrollView. Covers are SwiftUI `CoverBlock`s hosted in a small pool of
/// views laid over the cover column, only for albums on screen.
struct AlbumSongsTable: NSViewRepresentable {
    /// Table cells and cover hosts live outside SwiftUI's environment, so the stores come in explicitly.
    struct Stores {
        let library: LibraryStore
        let queue: PlaybackQueue
        let navigator: AppNavigator
        let hero: HeroTransition
        let artwork: ArtworkCache
    }

    let sections: [ArtistSection]
    /// Changes whenever the rows do, so the table reloads only then.
    let generation: Int
    let playOrder: [Track]
    let extras: [ExtraColumn]
    let customValues: [UUID: [PersistentID: String]]
    @Binding var artWidth: Double
    let currentID: PersistentID?
    let isPlaying: Bool
    /// The playing cover's colour (`\.playbackAccent`) for the playing row's marker and highlight.
    let playbackAccent: NSColor
    let bottomInset: CGFloat
    /// Changes when the sidebar's Songs item is clicked again at the top level.
    let scrollToTopToken: Int
    let stores: Stores

    static let artRange: ClosedRange<Double> = 90...360

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = SongsNSTableView()
        table.style = .plain
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.gridStyleMask = []
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.allowsColumnReordering = false
        table.allowsColumnSelection = false
        table.allowsTypeSelect = false
        table.floatsGroupRows = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.headerView = NSTableHeaderView()

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentView.postsBoundsChangedNotifications = true

        context.coordinator.attach(table, in: scroll)
        context.coordinator.update(from: self)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.update(from: self)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        private weak var table: SongsNSTableView?
        private weak var scroll: NSScrollView?
        private var parent: AlbumSongsTable?
        private var layout = AlbumSongsLayout(sections: [], metrics: Coordinator.metrics)
        private var generation: Int?
        private var extraIDs: [String]?
        private var currentID: PersistentID?
        private var isPlaying = false
        private var accent = NSColor.controlAccentColor
        private var covers: [PersistentID: NSHostingView<CoverBlock>] = [:]
        private var spareCovers: [NSHostingView<CoverBlock>] = []
        private var lastWidth: CGFloat = 0
        /// The remembered scroll offset is restored once, on the first load that has rows; until then the
        /// table's own zero offset mustn't overwrite it.
        private var restoredScroll = false
        private var scrollToTopToken: Int?
        /// Set while the code (not the user) changes column widths, so resize callbacks ignore it.
        private var adjustingColumns = false

        static let leadingPad: CGFloat = 20
        static let trailingPad: CGFloat = 18
        /// Header text and cell text start this far inside their column.
        static let inset: CGFloat = 4
        /// The cover column is the cover plus its inset and a gap before the songs.
        static let coverGap: CGFloat = 16

        static let bodyFont = NSFont.systemFont(ofSize: 13)
        static let currentFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        static let captionFont = NSFont.systemFont(ofSize: 10)
        static let digitsFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        static let extraFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)

        static func lineHeight(_ font: NSFont) -> CGFloat { ceil(NSLayoutManager().defaultLineHeight(for: font)) }

        /// Matches the SwiftUI cover block: body text rows with 5 pt padding, `.title3` headers,
        /// and a `.callout` title plus `.caption` year under each cover.
        static let metrics = AlbumSongsLayout.Metrics(
            song: lineHeight(bodyFont) + 10,
            songWithArtist: lineHeight(bodyFont) + 1 + lineHeight(captionFont) + 10,
            artist: lineHeight(.boldSystemFont(ofSize: 15)) + 17,
            coverTitle: 6 + lineHeight(.systemFont(ofSize: 12, weight: .medium)) + 2,
            year: 2 + lineHeight(captionFont)
        )

        private var artWidth: CGFloat { CGFloat(parent?.artWidth ?? 160) }

        func attach(_ table: SongsNSTableView, in scroll: NSScrollView) {
            self.table = table
            self.scroll = scroll
            table.dataSource = self
            table.delegate = self
            table.target = self
            table.doubleAction = #selector(doubleClicked)
            table.onReturn = { [weak self] in self?.playSelection() }
            let menu = NSMenu()
            menu.delegate = self
            table.menu = menu
            NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
                                                   name: NSView.boundsDidChangeNotification, object: scroll.contentView)
            NotificationCenter.default.addObserver(self, selector: #selector(scrolled),
                                                   name: NSView.frameDidChangeNotification, object: scroll.contentView)
        }

        func update(from parent: AlbumSongsTable) {
            let previousWidth = self.parent?.artWidth
            self.parent = parent
            guard let table, let scroll else { return }

            let ids = parent.extras.map(\.id)
            if ids != extraIDs {
                extraIDs = ids
                rebuildColumns(parent.extras)
                generation = nil // Cells depend on the columns.
            }
            if parent.generation != generation {
                generation = parent.generation
                layout = AlbumSongsLayout(sections: parent.sections, metrics: Self.metrics)
                table.deselectAll(nil)
                table.reloadData()
                currentID = parent.currentID
                isPlaying = parent.isPlaying
                if !restoredScroll, !layout.rows.isEmpty {
                    restoredScroll = true
                    if let y = parent.stores.navigator.scrollOffsets[.songs], y > 0 {
                        table.layoutSubtreeIfNeeded()
                        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                        scroll.reflectScrolledClipView(scroll.contentView)
                    }
                }
            } else if previousWidth != parent.artWidth, !adjustingColumns {
                // Changed outside the header drag (e.g. another window): resize the column to match.
                setCoverColumnWidth()
            }
            if parent.currentID != currentID || parent.isPlaying != isPlaying || parent.playbackAccent != accent {
                let rows = IndexSet([currentID, parent.currentID].compactMap { $0.flatMap { layout.rowOfTrack[$0] } })
                currentID = parent.currentID
                isPlaying = parent.isPlaying
                accent = parent.playbackAccent
                refresh(rows)
            }
            if scrollToTopToken != parent.scrollToTopToken {
                // The first value is just the current one, not a request.
                if scrollToTopToken != nil { scrollToTop() }
                scrollToTopToken = parent.scrollToTopToken
            }
            let insets = NSEdgeInsets(top: 0, left: 0, bottom: parent.bottomInset, right: 0)
            if scroll.contentInsets.bottom != insets.bottom {
                scroll.contentInsets = insets
                scroll.scrollerInsets = insets
            }
            layoutCovers()
        }

        private func scrollToTop() {
            guard let scroll, let table else { return }
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0.25
            NSAnimationContext.current.allowsImplicitAnimation = true
            table.scrollRowToVisible(0)
            NSAnimationContext.endGrouping()
            scroll.reflectScrolledClipView(scroll.contentView)
        }

        // MARK: Columns

        private func rebuildColumns(_ extras: [ExtraColumn]) {
            guard let table else { return }
            adjustingColumns = true
            defer { adjustingColumns = false }
            for column in table.tableColumns { table.removeTableColumn(column) }

            func add(_ id: String, _ title: String, width: CGFloat, alignment: NSTextAlignment = .left,
                     resizable: Bool = false, range: ClosedRange<CGFloat>? = nil) {
                let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
                column.title = title
                column.headerCell.alignment = alignment
                column.width = width
                if let range {
                    column.minWidth = range.lowerBound
                    column.maxWidth = range.upperBound
                } else {
                    column.minWidth = width
                    column.maxWidth = resizable ? 10_000 : width
                }
                column.resizingMask = resizable || range != nil ? .userResizingMask : []
                table.addTableColumn(column)
            }

            let coverExtra = Self.inset + Self.coverGap
            add("leading", "", width: Self.leadingPad)
            add("cover", "Album", width: artWidth + coverExtra,
                range: CGFloat(AlbumSongsTable.artRange.lowerBound) + coverExtra...CGFloat(AlbumSongsTable.artRange.upperBound) + coverExtra)
            add("number", "#", width: 30, alignment: .right)
            add("title", "Title", width: 200, resizable: true)
            for extra in extras {
                add(extra.id, extra.title, width: extra.width + Self.inset * 2, alignment: extra.numeric ? .right : .left)
            }
            add("time", "Time", width: 54 + Self.inset * 2, alignment: .right)
            add("trailing", "", width: Self.trailingPad)
            table.tableColumns.first { $0.identifier.rawValue == "title" }?.minWidth = 120
            fitTitleColumn()
        }

        private func setCoverColumnWidth() {
            guard let column = table?.tableColumns.first(where: { $0.identifier.rawValue == "cover" }) else { return }
            let target = artWidth + Self.inset + Self.coverGap
            guard abs(column.width - target) > 0.5 else { return }
            adjustingColumns = true
            column.width = target
            adjustingColumns = false
            coverWidthChanged()
        }

        /// Title takes whatever width the fixed columns leave, so the table never scrolls sideways.
        private func fitTitleColumn() {
            guard let table, let scroll,
                  let title = table.tableColumns.first(where: { $0.identifier.rawValue == "title" }) else { return }
            let others = table.tableColumns.filter { $0 !== title }.reduce(0) { $0 + $1.width }
            let width = max(title.minWidth, scroll.contentView.bounds.width - others)
            guard abs(title.width - width) > 0.5 else { return }
            let wasAdjusting = adjustingColumns
            adjustingColumns = true
            title.width = width
            adjustingColumns = wasAdjusting
        }

        func tableViewColumnDidResize(_ notification: Notification) {
            guard !adjustingColumns,
                  let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
                  column.identifier.rawValue == "cover" else { return }
            let width = (column.width - Self.inset - Self.coverGap).rounded()
            adjustingColumns = true
            parent?.artWidth = Double(width).clamped(to: AlbumSongsTable.artRange)
            adjustingColumns = false
            coverWidthChanged()
        }

        /// Bottom spacers grow or shrink with the cover, and the row highlight starts after it.
        private func coverWidthChanged() {
            guard let table else { return }
            let bottoms = IndexSet(layout.albums.map(\.bottom))
            // Zero duration: the table otherwise animates height changes, which lags behind the drag.
            NSAnimationContext.beginGrouping()
            NSAnimationContext.current.duration = 0
            table.noteHeightOfRows(withIndexesChanged: bottoms)
            NSAnimationContext.endGrouping()
            fitTitleColumn()
            table.enumerateAvailableRowViews { rowView, _ in
                (rowView as? SongRowView).map(self.configureGeometry)
            }
            layoutCovers()
        }

        // MARK: Rows

        func numberOfRows(in tableView: NSTableView) -> Int { layout.rows.count }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            layout.height(of: row, artWidth: artWidth)
        }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            if case .artist = layout.rows[row] { true } else { false }
        }

        func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
            proposed.filteredIndexSet { layout.isSong($0) }
        }

        func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
            if case .artist = layout.rows[row] { return nil }
            let id = NSUserInterfaceItemIdentifier("songRow")
            let rowView = tableView.makeView(withIdentifier: id, owner: nil) as? SongRowView ?? SongRowView()
            rowView.identifier = id
            switch layout.rows[row] {
            case .albumTop(let a): rowView.kind = layout.albums[a].isFirstInSection ? .spacer : .divider
            case .song(let a, let t, _): rowView.kind = .song; rowView.isCurrent = track(a, t).id == currentID
            default: rowView.kind = .spacer
            }
            rowView.highlight = accent
            if rowView.kind != .song { rowView.isCurrent = false }
            configureGeometry(rowView)
            return rowView
        }

        private func configureGeometry(_ rowView: SongRowView) {
            guard let table else { return }
            let number = table.column(withIdentifier: NSUserInterfaceItemIdentifier("number"))
            let time = table.column(withIdentifier: NSUserInterfaceItemIdentifier("time"))
            guard number >= 0, time >= 0 else { return }
            rowView.songArea = table.rect(ofColumn: number).minX - 2...table.rect(ofColumn: time).maxX + 2
            rowView.dividerArea = Self.leadingPad + Self.inset...table.bounds.width - Self.trailingPad - Self.inset
            rowView.needsDisplay = true
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            switch layout.rows[row] {
            case .artist(let s):
                guard let parent else { return nil }
                let header = tableView.makeView(withIdentifier: ArtistHeaderView.id, owner: nil) as? ArtistHeaderView ?? ArtistHeaderView()
                let section = parent.sections[s]
                let navigator = parent.stores.navigator
                header.configure(section, open: { navigator.openArtist(section.id) })
                return header
            case .song(let a, let t, _):
                guard let column = tableColumn?.identifier.rawValue else { return nil }
                return cell(column, track: track(a, t), album: layout.albums[a], in: tableView)
            default:
                return nil
            }
        }

        private func cell(_ column: String, track: Track, album span: AlbumSongsLayout.AlbumSpan, in tableView: NSTableView) -> NSView? {
            guard let parent else { return nil }
            let isCurrent = track.id == currentID
            switch column {
            case "number":
                let cell = tableView.makeView(withIdentifier: NumberCell.id, owner: nil) as? NumberCell ?? NumberCell()
                cell.configure(number: track.trackNumber, playing: isCurrent ? isPlaying : nil, color: accent)
                return cell
            case "title":
                let cell = tableView.makeView(withIdentifier: TitleCell.id, owner: nil) as? TitleCell ?? TitleCell()
                let albumArtist = parent.sections[span.section].groups[span.group].album.artist
                cell.configure(title: track.title, artist: track.displayArtist != albumArtist ? track.displayArtist : nil, isCurrent: isCurrent)
                return cell
            case "time":
                return textCell(track.duration.trackTime, font: Self.digitsFont, alignment: .right, in: tableView)
            default:
                guard let extra = parent.extras.first(where: { $0.id == column }) else { return nil }
                return textCell(extra.value(track, parent.customValues), font: Self.extraFont,
                                alignment: extra.numeric ? .right : .left, in: tableView)
            }
        }

        private func textCell(_ text: String, font: NSFont, alignment: NSTextAlignment, in tableView: NSTableView) -> NSView {
            let cell = tableView.makeView(withIdentifier: TextCell.id, owner: nil) as? TextCell ?? TextCell()
            cell.configure(text, font: font, alignment: alignment)
            return cell
        }

        private func track(_ a: Int, _ t: Int) -> Track {
            let span = layout.albums[a]
            return parent!.sections[span.section].groups[span.group].tracks[t]
        }

        /// Redraws rows whose playing state changed, without reloading the table.
        private func refresh(_ rows: IndexSet) {
            guard let table, !rows.isEmpty else { return }
            for row in rows where row < layout.rows.count {
                if let rowView = table.rowView(atRow: row, makeIfNecessary: false) as? SongRowView,
                   case .song(let a, let t, _) = layout.rows[row] {
                    rowView.isCurrent = track(a, t).id == currentID
                    rowView.highlight = accent
                }
            }
            table.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
        }

        // MARK: Covers

        @objc private func scrolled() {
            guard let scroll else { return }
            if restoredScroll { parent?.stores.navigator.scrollOffsets[.songs] = scroll.contentView.bounds.origin.y }
            let width = scroll.contentView.bounds.width
            if width != lastWidth {
                lastWidth = width
                fitTitleColumn()
                table?.enumerateAvailableRowViews { rowView, _ in
                    (rowView as? SongRowView).map(self.configureGeometry)
                }
            }
            layoutCovers()
        }

        private func layoutCovers() {
            guard let table, let parent else { return }
            let cover = table.column(withIdentifier: NSUserInterfaceItemIdentifier("cover"))
            let visible = table.rows(in: table.visibleRect)
            var shown = Set<PersistentID>()
            if cover >= 0, visible.length > 0, !layout.albums.isEmpty {
                let x = table.rect(ofColumn: cover).minX + Self.inset
                for a in layout.albumRange(overlapping: visible.location, visible.location + visible.length - 1) {
                    let span = layout.albums[a]
                    let album = parent.sections[span.section].groups[span.group].album
                    let block = CoverBlock(album: album, stores: parent.stores)
                    let host = covers[album.id] ?? dequeueCover(block, in: table)
                    if host.rootView.album != album { host.rootView = block }
                    covers[album.id] = host
                    host.isHidden = false
                    host.frame = CGRect(x: x, y: table.rect(ofRow: span.top).minY + layout.metrics.padding,
                                        width: artWidth, height: layout.coverHeight(album: a, artWidth: artWidth))
                    shown.insert(album.id)
                }
            }
            for (id, host) in covers where !shown.contains(id) {
                host.isHidden = true
                covers[id] = nil
                spareCovers.append(host)
            }
        }

        private func dequeueCover(_ block: CoverBlock, in table: NSTableView) -> NSHostingView<CoverBlock> {
            if let host = spareCovers.popLast() {
                host.rootView = block
                return host
            }
            let host = NSHostingView(rootView: block)
            host.sizingOptions = []
            // Behind the rows, which pass clicks in the cover column through (see SongRowView.hitTest).
            table.addSubview(host, positioned: .below, relativeTo: nil)
            return host
        }

        // MARK: Playing and menus

        @objc private func doubleClicked() {
            guard let table, table.clickedRow >= 0 else { return }
            play(from: table.clickedRow)
        }

        private func playSelection() {
            guard let row = table?.selectedRowIndexes.first else { return }
            play(from: row)
        }

        private func play(from row: Int) {
            guard let parent, case .song(_, _, let index) = layout.rows[row] else { return }
            parent.stores.queue.play(parent.playOrder, startAt: index)
        }

        /// The clicked song, or the whole selection when the click lands inside it.
        private func menuTracks() -> [Track] {
            guard let table else { return [] }
            let clicked = table.clickedRow
            let rows = clicked >= 0 && !table.selectedRowIndexes.contains(clicked) ? IndexSet(integer: clicked) : table.selectedRowIndexes
            return rows.compactMap { row in
                guard case .song(let a, let t, _) = layout.rows[row] else { return nil }
                return track(a, t)
            }
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            let tracks = menuTracks()
            guard let queue = parent?.stores.queue, !tracks.isEmpty else { return }
            // Mirrors TrackContextMenu.
            menu.addItem(MenuAction("Play", symbol: "play") { queue.play(tracks) })
            menu.addItem(MenuAction("Play Next", symbol: "text.line.first.and.arrowtriangle.forward") { queue.playNext(tracks) })
            menu.addItem(MenuAction("Add to Queue", symbol: "text.line.last.and.arrowtriangle.forward") { queue.addToQueue(tracks) })
        }
    }
}

// MARK: - Views

/// An album's cover, title and year, shown beside its songs. Not a tile: no hover or menu, and a click shows
/// the cover full-window, as on album pages. The rows below already play and open the album.
struct CoverBlock: View {
    let album: Album
    let stores: AlbumSongsTable.Stores
    @State private var probe = FrameProbe()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Sizes match AlbumTile's, which `AlbumSongsLayout.Metrics` was measured from.
            VStack(alignment: .leading, spacing: 6) {
                // A fixed base for the probe; the cover swaps placeholder for image inside it (see ArtistArtwork).
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { ArtworkView(albumID: album.id, cornerRadius: 10) }
                    .frameProbe(probe)
                    // Drawn from the outline: SwiftUI's `.shadow` was redrawn for every cover on every scrolled frame.
                    .background(ShapeShadow(shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                                            opacity: 0.15, radius: 6, y: 3))
                    .coverViewerOnClick(album, from: probe)
                Text(album.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            if album.year > 0 {
                Text(String(album.year))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(stores.library)
        .environment(stores.queue)
        .environment(stores.navigator)
        .environment(stores.hero)
        .environment(stores.artwork)
    }
}

/// Return plays the selection; everything else is the standard table.
final class SongsNSTableView: NSTableView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        // Return and keypad Enter.
        if event.keyCode == 36 || event.keyCode == 76 { onReturn?() } else { super.keyDown(with: event) }
    }
}

/// Draws the playing highlight and selection only over the song columns, and a divider between albums.
/// Clicks in the cover column fall through to the cover views behind the rows.
final class SongRowView: NSTableRowView {
    enum Kind { case song, spacer, divider }

    var kind = Kind.spacer
    var isCurrent = false { didSet { if isCurrent != oldValue { needsDisplay = true } } }
    /// The playing row's highlight colour (the playing cover's, see `\.playbackAccent`).
    var highlight = NSColor.controlAccentColor { didSet { if highlight != oldValue { needsDisplay = true } } }
    var songArea: ClosedRange<CGFloat> = 0...0
    var dividerArea: ClosedRange<CGFloat> = 0...0

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return local.x < songArea.lowerBound ? nil : super.hitTest(point)
    }

    private var highlightRect: NSRect {
        NSRect(x: songArea.lowerBound, y: 0, width: songArea.upperBound - songArea.lowerBound, height: bounds.height)
            .insetBy(dx: 0, dy: 0.5)
    }

    override func drawBackground(in dirtyRect: NSRect) {
        switch kind {
        case .divider:
            NSColor.separatorColor.setFill()
            NSRect(x: dividerArea.lowerBound, y: 0, width: dividerArea.upperBound - dividerArea.lowerBound, height: 1).fill()
        case .song where isCurrent && !isSelected:
            highlight.withAlphaComponent(0.14).setFill()
            NSBezierPath(roundedRect: highlightRect, xRadius: 6, yRadius: 6).fill()
        default:
            break
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard kind == .song else { return }
        (isEmphasized ? NSColor.selectedContentBackgroundColor : NSColor.unemphasizedSelectedContentBackgroundColor).setFill()
        NSBezierPath(roundedRect: highlightRect, xRadius: 6, yRadius: 6).fill()
    }
}

/// A flipped cell with manual layout; cheaper than Auto Layout for thousands of reused cells.
class FlippedCell: NSTableCellView {
    override var isFlipped: Bool { true }

    static func label() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.cell?.truncatesLastVisibleLine = true
        return label
    }
}

final class TextCell: FlippedCell {
    static let id = NSUserInterfaceItemIdentifier("text")
    private let label = FlippedCell.label()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.id
        addSubview(label)
        textField = label
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ text: String, font: NSFont, alignment: NSTextAlignment) {
        label.stringValue = text
        label.font = font
        label.alignment = alignment
        label.textColor = .secondaryLabelColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let height = AlbumSongsTable.Coordinator.lineHeight(label.font ?? .systemFont(ofSize: 13))
        let inset = AlbumSongsTable.Coordinator.inset
        label.frame = NSRect(x: inset, y: (bounds.height - height) / 2, width: bounds.width - inset * 2, height: height)
    }
}

final class TitleCell: FlippedCell {
    static let id = NSUserInterfaceItemIdentifier("title")
    private let title = FlippedCell.label()
    private let artist = FlippedCell.label()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.id
        artist.font = AlbumSongsTable.Coordinator.captionFont
        artist.textColor = .secondaryLabelColor
        addSubview(title)
        addSubview(artist)
        textField = title
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(title text: String, artist name: String?, isCurrent: Bool) {
        title.stringValue = text
        title.font = isCurrent ? AlbumSongsTable.Coordinator.currentFont : AlbumSongsTable.Coordinator.bodyFont
        artist.stringValue = name ?? ""
        artist.isHidden = name == nil
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let c = AlbumSongsTable.Coordinator.self
        let titleHeight = c.lineHeight(c.bodyFont)
        let artistHeight = artist.isHidden ? 0 : 1 + c.lineHeight(c.captionFont)
        let top = (bounds.height - titleHeight - artistHeight) / 2
        let width = bounds.width - c.inset * 2
        title.frame = NSRect(x: c.inset, y: top, width: width, height: titleHeight)
        artist.frame = NSRect(x: c.inset, y: top + titleHeight + 1, width: width, height: max(0, artistHeight - 1))
    }
}

/// The track number, or the equalizer for the playing song.
final class NumberCell: FlippedCell {
    static let id = NSUserInterfaceItemIdentifier("number")
    private let label = FlippedCell.label()
    private var indicator: NSHostingView<PlayingIndicator>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.id
        label.font = AlbumSongsTable.Coordinator.digitsFont
        label.alignment = .right
        label.textColor = .tertiaryLabelColor
        addSubview(label)
        textField = label
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `playing` is nil for songs that aren't current.
    func configure(number: Int, playing: Bool?, color: NSColor) {
        label.stringValue = number > 0 ? String(number) : "–"
        label.isHidden = playing != nil
        if let playing {
            if let indicator {
                indicator.rootView = PlayingIndicator(isAnimating: playing, color: Color(nsColor: color))
            } else {
                let host = NSHostingView(rootView: PlayingIndicator(isAnimating: playing, color: Color(nsColor: color)))
                host.sizingOptions = []
                addSubview(host)
                indicator = host
            }
            indicator?.isHidden = false
        } else {
            indicator?.isHidden = true
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let c = AlbumSongsTable.Coordinator.self
        let height = c.lineHeight(c.digitsFont)
        label.frame = NSRect(x: c.inset, y: (bounds.height - height) / 2, width: bounds.width - c.inset * 2, height: height)
        indicator?.frame = NSRect(x: bounds.width - c.inset - 13, y: (bounds.height - 12) / 2, width: 13, height: 12)
    }
}

/// The floating header above an album artist's albums. The name opens the artist's page.
final class ArtistHeaderView: FlippedCell {
    static let id = NSUserInterfaceItemIdentifier("artistHeader")
    private let background = NSVisualEffectView()
    private let name = NSButton(title: "", target: nil, action: nil)
    private let plainName = FlippedCell.label()
    private let chevron = NSImageView()
    private let detail = FlippedCell.label()
    private let separator = NSBox()
    private var open: (() -> Void)?

    private static let nameFont = NSFont.boldSystemFont(ofSize: 15)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = Self.id
        background.material = .headerView
        background.blendingMode = .withinWindow
        background.state = .followsWindowActiveState
        name.isBordered = false
        name.setButtonType(.momentaryChange)
        name.target = self
        name.action = #selector(openArtist)
        name.toolTip = "Show Artist"
        plainName.font = Self.nameFont
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        chevron.contentTintColor = .tertiaryLabelColor
        detail.font = AlbumSongsTable.Coordinator.captionFont
        detail.textColor = .secondaryLabelColor
        separator.boxType = .separator
        for view in [background, name, plainName, chevron, detail, separator] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ section: ArtistSection, open: @escaping () -> Void) {
        self.open = open
        // Compilations have no artist page, so "Various Artists" is plain text.
        let linked = section.groups.contains { !$0.album.isCompilation }
        name.attributedTitle = NSAttributedString(string: section.name, attributes: [
            .font: Self.nameFont, .foregroundColor: NSColor.labelColor,
        ])
        plainName.stringValue = section.name
        name.isHidden = !linked
        chevron.isHidden = !linked
        plainName.isHidden = linked
        let albums = section.groups.count, songs = section.songCount
        detail.stringValue = "\(albums) \(albums == 1 ? "album" : "albums") · \(songs) \(songs == 1 ? "song" : "songs")"
        needsLayout = true
    }

    @objc private func openArtist() { open?() }

    override func layout() {
        super.layout()
        background.frame = bounds
        separator.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        let x = AlbumSongsTable.Coordinator.leadingPad + AlbumSongsTable.Coordinator.inset
        let nameHeight = AlbumSongsTable.Coordinator.lineHeight(Self.nameFont)
        let y = (bounds.height - nameHeight) / 2
        let maxName = max(0, bounds.width * 0.6)
        let nameWidth = min(maxName, ceil((name.isHidden ? plainName.attributedStringValue : name.attributedTitle).size().width) + 4)
        name.frame = NSRect(x: x - 2, y: y, width: nameWidth, height: nameHeight)
        plainName.frame = NSRect(x: x, y: y, width: nameWidth, height: nameHeight)
        var next = x + nameWidth + 4
        if !chevron.isHidden {
            chevron.frame = NSRect(x: next, y: y + (nameHeight - 12) / 2 + 1, width: 8, height: 12)
            next += 18
        } else {
            next += 6
        }
        let detailHeight = AlbumSongsTable.Coordinator.lineHeight(AlbumSongsTable.Coordinator.captionFont)
        // Baseline-ish alignment with the name.
        detail.frame = NSRect(x: next, y: y + nameHeight - detailHeight - 2, width: max(0, bounds.width - next - 20), height: detailHeight)
    }
}

/// An NSMenuItem that runs a closure.
private final class MenuAction: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, symbol: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}
