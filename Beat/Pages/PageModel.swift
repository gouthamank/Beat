import Foundation

/// One block on a page: a smart filter it owns, plus how its result is shown.
struct PageElement: Codable, Identifiable, Hashable, Sendable {
    var filter: SmartFilter
    var appearance: ElementAppearance

    /// The filter's ID, so the engine's per-filter random seed and the results cache key stay stable.
    var id: UUID { filter.id }

    init(filter: SmartFilter, appearance: ElementAppearance? = nil) {
        self.filter = filter
        self.appearance = appearance ?? .defaults(for: filter.output)
    }

    /// The filter as evaluated. A sort override runs after every step, so it reorders
    /// what the filter returns without changing which items are in it.
    var effectiveFilter: SmartFilter {
        guard let key = appearance.sortOverride else { return filter }
        var filter = filter
        filter.steps.append(.sort([key]))
        return filter
    }

    /// A copy with fresh identity, for duplicating an element or a whole page.
    func withNewID() -> PageElement {
        var copy = self
        copy.filter.id = UUID()
        return copy
    }
}

struct ElementAppearance: Codable, Hashable, Sendable {
    enum Layout: String, Codable, CaseIterable, Sendable {
        case shelf, grid, list, coverFlow, timeline

        var title: String {
            switch self {
            case .shelf: "Shelf"
            case .grid: "Grid"
            case .list: "List"
            case .coverFlow: "Cover Flow"
            case .timeline: "Timeline"
            }
        }
    }
    enum Size: String, Codable, CaseIterable, Sendable { case small, medium, large }
    enum Spacing: String, Codable, CaseIterable, Sendable { case compact, regular, roomy }
    /// The order items take with more than one row (or list column): along each row, or down each column.
    enum Fill: String, Codable, CaseIterable, Sendable { case across, down }
    /// Timeline only: which end the years start from.
    enum TimelineOrder: String, Codable, CaseIterable, Sendable { case oldestFirst, newestFirst }
    /// Timeline only: how a busy year makes room. Wider keeps every year the same height (fixed rows); taller
    /// caps each year's columns, so busy years grow downwards and quiet ones shrink to fit.
    enum TimelineGrowth: String, Codable, CaseIterable, Sendable { case wider, taller }

    var layout: Layout = .shelf
    var size: Size = .medium
    /// Shelf: rows that scroll sideways together. Grid: rows shown before See All. List: rows per column.
    var rows = 1
    /// List only: items fill each column top to bottom, then the next column.
    var columns = 1
    var spacing: Spacing = .regular
    /// The fill chosen in Appearance; nil follows the layout (`effectiveFill`).
    var fill: Fill?
    /// Timeline only; nil is oldest first.
    var timelineOrder: TimelineOrder?
    /// Timeline only; nil is wider (fixed rows per year).
    var timelineGrowth: TimelineGrowth?
    /// Timeline only, when growing taller: the most columns a year takes; nil is 5.
    var timelineColumns: Int?

    static let timelineColumnRange = 1...8
    var effectiveTimelineColumns: Int { (timelineColumns ?? 5).clamped(to: Self.timelineColumnRange) }
    /// The column cap when years grow taller, nil when they keep one height.
    var timelineMaxColumns: Int? { timelineGrowth == .taller ? effectiveTimelineColumns : nil }
    var showHeader = true
    var showPlayButtons = true
    /// The title (and subtitle) under each tile; off shows art alone. Lists and songs keep their text.
    var showFooter = true
    var sortOverride: SortKey?

    /// `rows` value meaning "grow to fit every item", for grids and lists. Shelves always scroll instead.
    static let allRows = 0

    /// Whether this layout can show every item (Rows set to All).
    static func allowsAllRows(_ layout: Layout) -> Bool { layout == .grid || layout == .list }

    /// Fill makes a difference only with more than one row, or, for a list (or a timeline growing taller), more
    /// than one column.
    var fillApplies: Bool {
        switch layout {
        case .list: columns > 1
        case .timeline where timelineGrowth == .taller: effectiveTimelineColumns > 1
        default: rows != 1
        }
    }

    /// Covers read like a shelf, along each row; lists read like a tracklist, down each column.
    static func defaultFill(for layout: Layout) -> Fill { layout == .list ? .down : .across }

    /// The fill in use: the one chosen, else the layout's default, so switching layouts follows it.
    var effectiveFill: Fill { fill ?? Self.defaultFill(for: layout) }

    /// Choosing the layout's own default goes back to following the layout.
    mutating func setFill(_ value: Fill) { fill = value == Self.defaultFill(for: layout) ? nil : value }

    init() {}

    static func defaults(for output: ResultKind) -> ElementAppearance {
        var appearance = ElementAppearance()
        appearance.rows = defaultRows(layout: .shelf, output: output)
        return appearance
    }

    /// Songs show as a shelf or a list; artists and genres also as a grid; albums also as Cover Flow or a timeline.
    static func layouts(for output: ResultKind) -> [Layout] {
        switch output {
        case .songs: [.shelf, .list]
        case .albums: [.shelf, .grid, .list, .coverFlow, .timeline]
        case .artists, .genres: [.shelf, .grid, .list]
        }
    }

    static func rowRange(layout: Layout, output: ResultKind) -> ClosedRange<Int> {
        switch layout {
        case .shelf: output == .songs ? 1...6 : 1...3
        case .grid: 1...6
        case .list: 1...25
        case .coverFlow: 1...1
        // Rows of albums under each year.
        case .timeline: 1...3
        }
    }

    static let columnRange = 1...4

    static func defaultRows(layout: Layout, output: ResultKind) -> Int {
        switch layout {
        case .shelf: output == .songs ? 4 : 1
        case .grid: 2
        case .list: 10
        case .coverFlow, .timeline: 1
        }
    }

    /// Keeps the layout and rows valid after the element's output kind changes.
    mutating func fit(to output: ResultKind) {
        if !Self.layouts(for: output).contains(layout) {
            layout = output == .songs ? .list : .grid
            rows = Self.defaultRows(layout: layout, output: output)
        }
        if !(rows == Self.allRows && Self.allowsAllRows(layout)) {
            rows = rows.clamped(to: Self.rowRange(layout: layout, output: output))
        }
        columns = columns.clamped(to: Self.columnRange)
    }

    // Every field is optional on decode, so adding a setting never breaks an existing pages.json.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        layout = try c.decodeIfPresent(Layout.self, forKey: .layout) ?? .shelf
        size = try c.decodeIfPresent(Size.self, forKey: .size) ?? .medium
        rows = try c.decodeIfPresent(Int.self, forKey: .rows) ?? 1
        columns = try c.decodeIfPresent(Int.self, forKey: .columns) ?? 1
        spacing = try c.decodeIfPresent(Spacing.self, forKey: .spacing) ?? .regular
        fill = try c.decodeIfPresent(Fill.self, forKey: .fill)
        timelineOrder = try c.decodeIfPresent(TimelineOrder.self, forKey: .timelineOrder)
        timelineGrowth = try c.decodeIfPresent(TimelineGrowth.self, forKey: .timelineGrowth)
        timelineColumns = try c.decodeIfPresent(Int.self, forKey: .timelineColumns)
        showHeader = try c.decodeIfPresent(Bool.self, forKey: .showHeader) ?? true
        showPlayButtons = try c.decodeIfPresent(Bool.self, forKey: .showPlayButtons) ?? true
        showFooter = try c.decodeIfPresent(Bool.self, forKey: .showFooter) ?? true
        sortOverride = try c.decodeIfPresent(SortKey.self, forKey: .sortOverride)
    }
}

/// The Timeline layout's years: item indices grouped by year, in year order, keeping the element's own order
/// within a year. Items without a year (0) come last under "No year" (nil), whichever way the years run.
enum TimelineYears {
    static func group(_ count: Int, year: (Int) -> Int, newestFirst: Bool) -> [(year: Int?, indices: [Int])] {
        var byYear: [Int: [Int]] = [:]
        for index in 0..<max(count, 0) { byYear[year(index), default: []].append(index) }
        let years = byYear.keys.filter { $0 > 0 }.sorted(by: newestFirst ? (>) : (<))
        var groups: [(year: Int?, indices: [Int])] = years.map { ($0, byYear[$0]!) }
        let unknown = byYear.filter { $0.key <= 0 }.values.flatMap { $0 }.sorted()
        if !unknown.isEmpty { groups.append((nil, unknown)) }
        return groups
    }

    /// One year's mini-grid as columns of positions within the year. With `maxColumns` nil every year has
    /// `rows` rows (all the same height; busy years get wider). With a cap, a year is as many columns as it
    /// needs up to the cap (quiet years shrink to fit) and grows downwards: 20 albums with a cap of 5 are
    /// 4 rows tall.
    static func grid(count: Int, rows: Int, maxColumns: Int?, fill: ElementAppearance.Fill) -> [[Int]] {
        guard count > 0 else { return [] }
        guard let maxColumns else { return ElementPaging.columns(count: count, rows: rows, fill: fill) }
        let width = min(count, max(maxColumns, 1))
        switch fill {
        case .across: return (0..<width).map { Array(stride(from: $0, to: count, by: width)) }
        case .down: return ElementPaging.columns(count: count, rows: ElementPaging.rowsNeeded(count: count, columns: width), fill: .down)
        }
    }
}

/// Column and row arithmetic for grid and list layouts.
enum ElementPaging {
    static func columnsNeeded(count: Int, rows: Int) -> Int {
        rows > 0 ? (count + rows - 1) / rows : 0
    }

    static func rowsNeeded(count: Int, columns: Int) -> Int {
        columns > 0 ? (count + columns - 1) / columns : 0
    }

    /// More items than one screenful of rows × columns, so the rest scroll sideways.
    static func isCapped(count: Int, rows: Int, columns: Int) -> Bool {
        rows > 0 && count > rows * columns
    }

    /// Item indices grouped into on-screen columns, each top to bottom. Down: runs of `rows`, column after
    /// column. Across: each row runs all the way along, the first holding the first ⌈count / rows⌉ items, the
    /// next row the next ones, and they scroll sideways together.
    static func columns(count: Int, rows: Int, fill: ElementAppearance.Fill) -> [[Int]] {
        let rows = max(rows, 1)
        guard count > 0 else { return [] }
        if fill == .down || rows == 1 {
            return stride(from: 0, to: count, by: rows).map { Array($0..<min($0 + rows, count)) }
        }
        let width = columnsNeeded(count: count, rows: rows)
        return (0..<width).map { Array(stride(from: $0, to: count, by: width)) }
    }
}

struct Page: Codable, Hashable, Sendable {
    var elements: [PageElement] = []
}

/// A sidebar item: a folder of further nodes, or a page. Pages are leaves.
struct SidebarNode: Identifiable, Hashable, Sendable {
    enum Content: Hashable, Sendable {
        case folder([SidebarNode])
        case page(Page)
    }

    var id = UUID()
    var name: String
    var symbol: String
    var content: Content

    static func folder(_ name: String, symbol: String = "folder", _ children: [SidebarNode] = []) -> SidebarNode {
        SidebarNode(name: name, symbol: symbol, content: .folder(children))
    }

    static func page(_ name: String, symbol: String = "rectangle.grid.1x2", _ elements: [PageElement] = []) -> SidebarNode {
        SidebarNode(name: name, symbol: symbol, content: .page(Page(elements: elements)))
    }

    var isFolder: Bool { if case .folder = content { true } else { false } }

    /// Children for `OutlineGroup`: nil for pages, so they show no disclosure triangle.
    var children: [SidebarNode]? { if case .folder(let c) = content { c } else { nil } }

    var page: Page? { if case .page(let p) = content { p } else { nil } }

    /// A deep copy with new IDs for this node, its descendants and every element.
    func withNewIDs() -> SidebarNode {
        var copy = self
        copy.id = UUID()
        switch content {
        case .folder(let children): copy.content = .folder(children.map { $0.withNewIDs() })
        case .page(let page): copy.content = .page(Page(elements: page.elements.map { $0.withNewID() }))
        }
        return copy
    }
}

extension SidebarNode: Codable {
    // Plain keys ("folder" / "page") rather than the synthesized "_0" form, so the file stays readable.
    private enum CodingKeys: String, CodingKey { case id, name, symbol, folder, page }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decode(String.self, forKey: .symbol)
        if let children = try c.decodeIfPresent([SidebarNode].self, forKey: .folder) {
            content = .folder(children)
        } else {
            content = .page(try c.decode(Page.self, forKey: .page))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(symbol, forKey: .symbol)
        switch content {
        case .folder(let children): try c.encode(children, forKey: .folder)
        case .page(let page): try c.encode(page, forKey: .page)
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
