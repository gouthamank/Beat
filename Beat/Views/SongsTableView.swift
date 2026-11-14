import SwiftUI

/// A songs element's See All, where order matters (e.g. Most Played): a customizable, sortable table,
/// with the count, Play/Shuffle and the covers toggle in the toolbar. Library ▸ Songs uses `AlbumSongsView` instead.
struct SongsTableView: View {
    let title: String
    let tracks: [Track]

    @Environment(PlaybackQueue.self) private var queue
    @Environment(PageStore.self) private var pages
    @Environment(LibraryStore.self) private var library
    @Environment(ArtworkCache.self) private var artwork
    /// Read here: table cells are AppKit-hosted and don't get the environment.
    @Environment(\.playbackAccent) private var playbackAccent
    @AppStorage("songs.showCovers") private var showCovers = true
    @State private var model = SongsModel()
    @State private var sortOrder: [TrackSort] = []
    @State private var selection = Set<Track.ID>()
    @State private var search = ""
    /// Shown, ordered and sized columns, restored on relaunch.
    @SceneStorage("SongsColumns") private var columns = TableColumnCustomization<Track>()

    var body: some View {
        table
            .navigationTitle(title)
            .pageSubtitle(SongsSummary.text(model.rows))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Toggle(isOn: $showCovers) { Label("Covers", systemImage: "photo") }
                        .help(showCovers ? "Hide Covers" : "Show Covers")
                }
                PlayShuffleToolbar(tracks: model.rows)
            }
            .searchable(text: $search, placement: .page, prompt: "Songs")
            .autocorrectionDisabled()
        .onAppear { refresh(debounce: false) }
        .onChange(of: search) { refresh(debounce: true) }
        .onChange(of: sortOrder) { refresh(debounce: false) }
        .onChange(of: pages.customFields) { refresh(debounce: false) }
        .onChange(of: tracks) { refresh(debounce: false) }
    }

    private func refresh(debounce: Bool) {
        model.update(tracks: tracks, search: search, sort: sortOrder, fields: pages.customFields,
                     albums: library.snapshot.albums, searchText: library.snapshot.trackSearchText, grouped: false,
                     debounce: debounce)
    }

    // MARK: Table

    private var table: some View {
        Table(model.rows, selection: $selection, sortOrder: $sortOrder, columnCustomization: $columns) {
            Group {
                TableColumn("Title", sortUsing: TrackSort(column: .title)) { titleCell($0) }
                    .width(min: 160, ideal: 280)
                    .customizationID("title")
                    .disabledCustomizationBehavior(.visibility)
                TableColumn("Artist", sortUsing: TrackSort(column: .artist)) { Text($0.displayArtist) }
                    .width(min: 100, ideal: 180)
                    .customizationID("artist")
                TableColumn("Album", sortUsing: TrackSort(column: .album)) { Text($0.album) }
                    .width(min: 100, ideal: 200)
                    .customizationID("album")
                TableColumn("Album Artist", sortUsing: TrackSort(column: .albumArtist)) { Text($0.albumArtist) }
                    .width(min: 100, ideal: 160)
                    .customizationID("albumArtist")
                    .defaultVisibility(.hidden)
                TableColumn("Time", sortUsing: TrackSort(column: .time)) { Text($0.duration.trackTime).monospacedDigit() }
                    .width(54)
                    .customizationID("time")
                TableColumn("#", sortUsing: TrackSort(column: .trackNumber)) { number($0.trackNumber) }
                    .width(34)
                    .customizationID("trackNumber")
                    .defaultVisibility(.hidden)
                TableColumn("Disc", sortUsing: TrackSort(column: .discNumber)) { number($0.discNumber) }
                    .width(38)
                    .customizationID("discNumber")
                    .defaultVisibility(.hidden)
                TableColumn("Genre", sortUsing: TrackSort(column: .genre)) { Text($0.genre) }
                    .width(min: 60, ideal: 110)
                    .customizationID("genre")
                TableColumn("Year", sortUsing: TrackSort(column: .year)) { number($0.year) }
                    .width(48)
                    .customizationID("year")
                TableColumn("Plays", sortUsing: TrackSort(column: .plays)) { Text("\($0.playCount)").monospacedDigit() }
                    .width(48)
                    .customizationID("plays")
            }
            Group {
                TableColumn("Skips", sortUsing: TrackSort(column: .skips)) { Text("\($0.skipCount)").monospacedDigit() }
                    .width(48)
                    .customizationID("skips")
                    .defaultVisibility(.hidden)
                TableColumn("Rating", sortUsing: TrackSort(column: .rating)) { Text(String(repeating: "★", count: $0.stars)) }
                    .width(70)
                    .customizationID("rating")
                    .defaultVisibility(.hidden)
                TableColumn("BPM", sortUsing: TrackSort(column: .bpm)) { number($0.bpm) }
                    .width(44)
                    .customizationID("bpm")
                    .defaultVisibility(.hidden)
                TableColumn("Bit Rate", sortUsing: TrackSort(column: .bitRate)) { Text("\($0.bitrate) kbps").monospacedDigit() }
                    .width(72)
                    .customizationID("bitRate")
                    .defaultVisibility(.hidden)
                TableColumn("Sample Rate", sortUsing: TrackSort(column: .sampleRate)) { Text("\($0.sampleRate) Hz").monospacedDigit() }
                    .width(84)
                    .customizationID("sampleRate")
                    .defaultVisibility(.hidden)
                TableColumn("Kind", sortUsing: TrackSort(column: .kind)) { Text($0.kind) }
                    .width(min: 80, ideal: 130)
                    .customizationID("kind")
                    .defaultVisibility(.hidden)
                TableColumn("Composer", sortUsing: TrackSort(column: .composer)) { Text($0.composer) }
                    .width(min: 80, ideal: 140)
                    .customizationID("composer")
                    .defaultVisibility(.hidden)
                TableColumn("Grouping", sortUsing: TrackSort(column: .grouping)) { Text($0.grouping) }
                    .width(min: 80, ideal: 120)
                    .customizationID("grouping")
                    .defaultVisibility(.hidden)
                TableColumn("Comments", sortUsing: TrackSort(column: .comments)) { Text($0.comments) }
                    .width(min: 80, ideal: 160)
                    .customizationID("comments")
                    .defaultVisibility(.hidden)
                TableColumn("Date Added", sortUsing: TrackSort(column: .dateAdded)) { date($0.dateAdded) }
                    .width(min: 80, ideal: 100)
                    .customizationID("dateAdded")
                    .defaultVisibility(.hidden)
            }
            Group {
                TableColumn("Last Played", sortUsing: TrackSort(column: .lastPlayed)) { date($0.lastPlayed) }
                    .width(min: 80, ideal: 100)
                    .customizationID("lastPlayed")
                    .defaultVisibility(.hidden)
                TableColumn("Date Modified", sortUsing: TrackSort(column: .dateModified)) { date($0.dateModified) }
                    .width(min: 80, ideal: 100)
                    .customizationID("dateModified")
                    .defaultVisibility(.hidden)
            }
            TableColumnForEach(pages.customFields) { field in
                TableColumn(field.name, sortUsing: TrackSort(column: .custom(field.id))) { track in
                    Text(model.customValues[field.id]?[track.id] ?? "").monospacedDigit()
                }
                .width(min: 70, ideal: 100)
                .customizationID("custom-\(field.id.uuidString)")
                .defaultVisibility(.hidden)
            }
        }
        #if os(macOS)
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        #else
        .tableStyle(.inset)
        #endif
        .contextMenu(forSelectionType: Track.ID.self) { ids in
            TrackContextMenu(tracks: model.rows.filter { ids.contains($0.id) })
        } primaryAction: { ids in
            let rows = model.rows
            guard let start = rows.firstIndex(where: { ids.contains($0.id) }) else { return }
            queue.play(rows, startAt: start)
        }
    }

    // MARK: Cells

    /// Compact: the cover is no taller than the text, so rows stay as dense as Music's.
    private func titleCell(_ track: Track) -> some View {
        let isCurrent = queue.current?.id == track.id
        return HStack(spacing: 6) {
            if showCovers {
                ArtworkView(albumID: track.albumID, cornerRadius: 3)
                    // Table cells live in AppKit-hosted rows that don't inherit environment objects.
                    .environment(artwork)
                    .frame(width: 18, height: 18)
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 3).fill(.black.opacity(0.45))
                            PlayingIndicator(isAnimating: queue.isPlaying, color: .white)
                                .scaleEffect(0.5)
                        }
                    }
            } else if isCurrent {
                PlayingIndicator(isAnimating: queue.isPlaying, color: playbackAccent)
                    .scaleEffect(0.6)
                    .frame(width: 14)
            }
            Text(track.title)
                .fontWeight(isCurrent ? .semibold : .regular)
                .lineLimit(1)
        }
    }

    private func number(_ value: Int) -> some View {
        Text(value > 0 ? String(value) : "").monospacedDigit()
    }

    private func date(_ value: Date?) -> some View {
        Text(value?.formatted(date: .abbreviated, time: .omitted) ?? "")
    }
}

/// The table's rows, filtered and sorted off the main actor so typing and sorting stay smooth with ~20k songs.
@MainActor
@Observable
final class SongsModel {
    /// The filtered, sorted songs (List order).
    private(set) var rows: [Track] = []
    /// The same songs under their albums, for Album by Artist.
    private(set) var groups: [SongGroup] = []
    /// Those albums under their album artists, for the pinned artist headers.
    private(set) var sections: [ArtistSection] = []
    /// `sections` as the Mac table's rows, built off the main actor with them; nil without `layoutMetrics`.
    private(set) var layout: AlbumSongsLayout?
    /// The songs in the order shown, for Play, Shuffle and double-click.
    private(set) var playOrder: [Track] = []
    /// Custom field values per field and track, worked out once per library or field change.
    private(set) var customValues: [UUID: [PersistentID: String]] = [:]
    /// Bumped with every new set of rows, so an AppKit table can tell when to reload.
    private(set) var generation = 0

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var valuesKey: Int?

    func update(tracks: [Track], search: String, sort: [TrackSort], fields: [CustomField], albums: [Album],
                searchText: [PersistentID: String], grouped: Bool, layoutMetrics: AlbumSongsLayout.Metrics? = nil,
                debounce: Bool) {
        task?.cancel()
        // A cheap identity for "same tracks and fields", so values aren't re-extracted on every keystroke.
        var hasher = Hasher()
        hasher.combine(fields)
        hasher.combine(tracks.count)
        hasher.combine(tracks.first?.id)
        hasher.combine(tracks.last?.id)
        let key = hasher.finalize()
        let cached = key == valuesKey ? customValues : nil

        task = Task {
            if debounce {
                // Just long enough to skip the keystrokes of a word typed quickly; the search itself is cheap now.
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
            }
            let (values, rows, groups, sections, layout, playOrder) = await Task.detached(priority: .userInitiated) {
                let values = cached ?? SongsQuery.customValues(fields, for: tracks)
                let rows = SongsQuery.apply(tracks, search: search, sort: sort, customValues: values, searchText: searchText)
                guard grouped else { return (values, rows, [SongGroup](), [ArtistSection](), AlbumSongsLayout?.none, rows) }
                let groups = SongsQuery.groupByAlbum(rows, albums: albums)
                let sections = SongsQuery.sectionsByArtist(groups)
                let layout = layoutMetrics.map { AlbumSongsLayout(sections: sections, metrics: $0) }
                return (values, rows, groups, sections, layout, groups.flatMap(\.tracks))
            }.value
            guard !Task.isCancelled else { return }
            customValues = values
            valuesKey = key
            self.rows = rows
            self.groups = groups
            self.sections = sections
            self.layout = layout
            self.playOrder = playOrder
            generation += 1
        }
    }
}

/// "20,113 songs · 58 days", the toolbar subtitle of a songs page.
enum SongsSummary {
    static func text(_ rows: [Track]) -> String {
        let total = rows.reduce(0) { $0 + $1.duration }
        let time = Duration.seconds(total).formatted(.units(allowed: [.days, .hours, .minutes], width: .wide, maximumUnitCount: 2))
        let size = rows.reduce(Int64(0)) { $0 + $1.fileSize }
        return "\(rows.count.counted("song")) · \(time)" + size.fileSizeSuffix
    }
}

// MARK: - Album by Artist

/// Library ▸ Songs: songs grouped under their albums, cover on the left, in artist → year → title order.
/// The album column carries the year (it's the same for every song on an album). Each song row always
/// shows its track number, title (with the artist underneath when it differs from the album artist)
/// and duration; other columns are optional and chosen from the Columns menu. The list itself is an
/// AppKit table (`AlbumSongsTable`) so scrolling stays smooth with ~20k songs.
struct AlbumSongsView: View {
    let title: String
    let tracks: [Track]

    @Environment(PlaybackQueue.self) private var queue
    @Environment(PageStore.self) private var pages
    @Environment(LibraryStore.self) private var library
    @Environment(AppNavigator.self) private var navigator
    @Environment(HeroTransition.self) private var hero
    @Environment(\.playbackAccent) private var playbackAccent
    @Environment(ArtworkCache.self) private var artwork
    /// Width of the cover column, dragged by the user in the column header.
    @AppStorage("songs.albumArtWidth") private var artWidth = 160.0
    /// IDs of the optional columns shown, comma-separated.
    @AppStorage("songs.albumColumns") private var shownColumnIDs = "genre,plays"
    /// The movable columns' order, as dragged on the Mac (`SongColumnOrder`).
    @AppStorage(SongColumnOrder.key) private var columnOrder = ""
    /// The optional columns' widths, as dragged on the Mac (`SongColumnWidths`).
    @AppStorage(SongColumnWidths.key) private var columnWidths = ""
    @State private var model = SongsModel()

    /// Library ▸ Songs is the only user of this view, so its search is remembered under `.songs`.
    private var search: String { navigator.searches[.songs] ?? "" }

    private var columns: [ExtraColumn] { ExtraColumn.all(customFields: pages.customFields) }
    private var shown: [ExtraColumn] {
        let ids = Set(shownColumnIDs.split(separator: ",").map(String.init))
        return columns.filter { ids.contains($0.id) }
    }
    /// #, Title, the shown optional columns and Time, in the order they were dragged to.
    private var order: [String] {
        SongColumnOrder.merged(saved: SongColumnOrder.parse(columnOrder),
                               shown: SongColumnOrder.leading + shown.map(\.id) + SongColumnOrder.trailing)
    }

    var body: some View {
        AlbumSongsTable(
            sections: model.sections,
            layout: model.layout,
            generation: model.generation,
            playOrder: model.playOrder,
            extras: shown,
            columnSettings: SongColumnSettings(order: order, widths: SongColumnWidths.parse(columnWidths),
                                               moved: { saveOrder($0) }, resized: { saveWidth($1, of: $0) }),
            customValues: model.customValues,
            artWidth: $artWidth,
            currentID: queue.current?.id,
            isPlaying: queue.isPlaying,
            playbackAccent: PlatformColor(playbackAccent),
            bottomInset: queue.current == nil ? 0 : NowPlayingBar.reservedHeight,
            scrollToTopToken: navigator.scrollToTop?.item == .songs ? navigator.scrollToTop?.token ?? 0 : 0,
            highlight: navigator.songsHighlight,
            stores: .init(library: library, queue: queue, navigator: navigator, hero: hero, artwork: artwork)
        )
        .overlay {
            if model.groups.isEmpty, !search.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .navigationTitle(title)
        .pageSubtitle(SongsSummary.text(model.rows))
        .toolbar {
            #if os(macOS)
            // iPad and iPhone list songs without the optional columns, so there's nothing to choose.
            ToolbarItem(placement: .primaryAction) { columnsMenu }
            #endif
            PlayShuffleToolbar(tracks: model.playOrder)
        }
        .searchable(text: navigator.search(.songs, else: .constant("")), placement: .page, prompt: "Songs")
        .autocorrectionDisabled()
        .onAppear { refresh(debounce: false) }
        .onChange(of: search) { refresh(debounce: true) }
        .onChange(of: pages.customFields) { refresh(debounce: false) }
        .onChange(of: tracks) { refresh(debounce: false) }
    }

    private func refresh(debounce: Bool) {
        model.update(tracks: tracks, search: search, sort: [], fields: pages.customFields,
                     albums: library.snapshot.albums, searchText: library.snapshot.trackSearchText, grouped: true,
                     layoutMetrics: AlbumSongsTable.layoutMetrics, debounce: debounce)
    }

    private var columnsMenu: some View {
        Menu {
            ForEach(columns) { column in
                Toggle(column.title, isOn: Binding(
                    get: { shown.contains { $0.id == column.id } },
                    set: { setShown(column.id, $0) }
                ))
            }
        } label: {
            Label("Columns", systemImage: "tablecells")
        }
        .help("Choose Columns")
    }

    private func saveOrder(_ displayed: [String]) {
        let known = Set(SongColumnOrder.leading + columns.map(\.id) + SongColumnOrder.trailing)
        columnOrder = SongColumnOrder.saving(displayed, over: SongColumnOrder.parse(columnOrder), known: known)
            .joined(separator: ",")
    }

    /// Widths of columns that no longer exist (a deleted custom field's) are dropped on the way.
    private func saveWidth(_ width: CGFloat, of id: String) {
        let known = Set(columns.map(\.id))
        var widths = SongColumnWidths.parse(columnWidths).filter { known.contains($0.key) }
        widths[id] = width
        columnWidths = SongColumnWidths.store(widths)
    }

    private func setShown(_ id: String, _ on: Bool) {
        var ids = shownColumnIDs.split(separator: ",").map(String.init).filter { $0 != id }
        if on { ids.append(id) }
        shownColumnIDs = ids.joined(separator: ",")
    }
}

/// An optional Album by Artist column: a fixed width and a text value per song.
struct ExtraColumn: Identifiable {
    let id: String
    let title: String
    let width: CGFloat
    var numeric = false
    let value: (Track, [UUID: [PersistentID: String]]) -> String

    static func all(customFields: [CustomField]) -> [ExtraColumn] {
        func count(_ n: Int) -> String { n > 0 ? String(n) : "" }
        func date(_ d: Date?) -> String { d?.formatted(date: .abbreviated, time: .omitted) ?? "" }
        let builtIn: [ExtraColumn] = [
            ExtraColumn(id: "album", title: "Album", width: 160) { t, _ in t.album },
            ExtraColumn(id: "albumArtist", title: "Album Artist", width: 140) { t, _ in t.albumArtist },
            ExtraColumn(id: "genre", title: "Genre", width: 100) { t, _ in t.genre },
            ExtraColumn(id: "plays", title: "Plays", width: 44, numeric: true) { t, _ in String(t.playCount) },
            ExtraColumn(id: "skips", title: "Skips", width: 44, numeric: true) { t, _ in String(t.skipCount) },
            ExtraColumn(id: "rating", title: "Rating", width: 64) { t, _ in String(repeating: "★", count: t.stars) },
            ExtraColumn(id: "bpm", title: "BPM", width: 40, numeric: true) { t, _ in count(t.bpm) },
            ExtraColumn(id: "discNumber", title: "Disc", width: 36, numeric: true) { t, _ in count(t.discNumber) },
            ExtraColumn(id: "bitRate", title: "Bit Rate", width: 70, numeric: true) { t, _ in "\(t.bitrate) kbps" },
            ExtraColumn(id: "sampleRate", title: "Sample Rate", width: 82, numeric: true) { t, _ in "\(t.sampleRate) Hz" },
            ExtraColumn(id: "kind", title: "Kind", width: 110) { t, _ in t.kind },
            ExtraColumn(id: "composer", title: "Composer", width: 120) { t, _ in t.composer },
            ExtraColumn(id: "grouping", title: "Grouping", width: 110) { t, _ in t.grouping },
            ExtraColumn(id: "comments", title: "Comments", width: 140) { t, _ in t.comments },
            ExtraColumn(id: "dateAdded", title: "Date Added", width: 90) { t, _ in date(t.dateAdded) },
            ExtraColumn(id: "lastPlayed", title: "Last Played", width: 90) { t, _ in date(t.lastPlayed) },
            ExtraColumn(id: "dateModified", title: "Date Modified", width: 90) { t, _ in date(t.dateModified) },
        ]
        let custom = customFields.map { field in
            ExtraColumn(id: "custom-\(field.id.uuidString)", title: field.name, width: 90) { t, values in
                values[field.id]?[t.id] ?? ""
            }
        }
        return builtIn + custom
    }
}


/// The order of Library ▸ Songs' movable columns (#, Title, Time and the optional ones), dragged by their headers on
/// the Mac and saved as comma-separated ids. Columns hidden from the Columns menu keep their place in the saved
/// order, so one shown again comes back where it was. Pure, for tests.
enum SongColumnOrder {
    static let key = "songs.columnOrder"
    /// Always shown, in their default order around the optional columns: #, Title, …, Time.
    static let leading = ["number", "title"]
    static let trailing = ["time"]

    static func parse(_ stored: String) -> [String] { stored.split(separator: ",").map(String.init) }

    /// The columns to show, in order. `shown` is the default order (#, Title, the optional columns, Time); a column the
    /// saved order has never placed goes just before Time.
    static func merged(saved: [String], shown: [String]) -> [String] {
        guard !saved.isEmpty else { return shown }
        var order = saved.filter(shown.contains)
        for id in shown where !order.contains(id) {
            order.insert(id, at: order.firstIndex(of: "time") ?? order.endIndex)
        }
        return order
    }

    /// The order to save after a move: `displayed` fills the places the shown columns had, so hidden ones stay put.
    /// Ids no longer `known` (a deleted custom field's column) are dropped.
    static func saving(_ displayed: [String], over saved: [String], known: Set<String>) -> [String] {
        var order = saved.filter { known.contains($0) }
        for id in displayed where !order.contains(id) { order.append(id) }
        let places = order.indices.filter { displayed.contains(order[$0]) }
        for (place, id) in zip(places, displayed) { order[place] = id }
        return order
    }
}

/// The widths of Library ▸ Songs' optional columns, dragged by their header edges on the Mac and saved as
/// "id:width" pairs. Pure, for tests.
enum SongColumnWidths {
    static let key = "songs.columnWidths"

    static func parse(_ stored: String) -> [String: CGFloat] {
        var widths: [String: CGFloat] = [:]
        for pair in stored.split(separator: ",") {
            let parts = pair.split(separator: ":")
            guard parts.count == 2, let width = Double(parts[1]), width > 0 else { continue }
            widths[String(parts[0])] = CGFloat(width)
        }
        return widths
    }

    /// Sorted by id, so the same widths always save the same text.
    static func store(_ widths: [String: CGFloat]) -> String {
        widths.sorted { $0.key < $1.key }.map { "\($0.key):\(Int($0.value.rounded()))" }.joined(separator: ",")
    }

    /// How far a column whose default width is `base` can be dragged: narrow enough to tuck away, wide enough for long
    /// composers and comments.
    static func range(base: CGFloat) -> ClosedRange<CGFloat> {
        max(40, (base * 0.6).rounded())...max(320, base * 3)
    }
}

/// Library ▸ Songs' column order and widths, and how the Mac table reports header drags back to be saved.
struct SongColumnSettings {
    /// #, Title, the shown optional columns and Time, left to right (`SongColumnOrder`).
    var order: [String]
    /// Saved widths of optional columns; the rest use their defaults (`SongColumnWidths`).
    var widths: [String: CGFloat]
    var moved: ([String]) -> Void
    var resized: (String, CGFloat) -> Void
}
