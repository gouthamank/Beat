import SwiftUI

// Keyboard navigation for grids, shelves and list columns, as in Music and Finder: Tab focuses the whole
// collection as one stop, arrow keys move a highlight between items, Space or Return opens the highlighted
// one. Items open themselves (they know how: the zoom, playing a song), so the grid only says which.

/// The order a collection lays its items out in, which decides where each arrow key goes.
enum GridOrder: Equatable, Sendable {
    /// Left to right, then the next row: the Library grids, and element grids showing every row.
    case rows(columns: Int)
    /// Top to bottom, then the next column.
    case columns(rows: Int)
    /// Exactly as laid out: item indices per on-screen column, each top to bottom (`ElementPaging.columns`),
    /// for page elements, which fill across or down.
    case slots([[Int]])
}

enum GridMove: Sendable {
    case left, right, up, down
}

enum GridNavigation {
    /// The item an arrow key moves to from `index`; `index` itself at an edge.
    static func move(_ direction: GridMove, from index: Int, count: Int, order: GridOrder) -> Int {
        guard count > 0 else { return index }
        let index = min(max(index, 0), count - 1)
        let target: Int
        switch order {
        case .rows(let columns):
            let columns = max(columns, 1)
            switch direction {
            // Left and right carry on into the next or previous row, as in Finder.
            case .left: target = index - 1
            case .right: target = index + 1
            case .up: target = index - columns
            // Into a shorter last row: the item below, or its last item.
            case .down: target = (index / columns + 1) * columns < count ? min(index + columns, count - 1) : index
            }
        case .columns(let rows):
            let rows = max(rows, 1)
            switch direction {
            // Up and down stay in the column; a one-row shelf only moves sideways.
            case .up: target = index % rows == 0 ? index : index - 1
            case .down: target = index % rows == rows - 1 ? index : index + 1
            case .left: target = index - rows
            case .right: target = (index / rows + 1) * rows < count ? min(index + rows, count - 1) : index
            }
        case .slots(let columns):
            guard let column = columns.firstIndex(where: { $0.contains(index) }),
                  let row = columns[column].firstIndex(of: index) else { return index }
            switch direction {
            // Up and down stay in the column; left and right keep the row, or the nearest one in a shorter column.
            case .up: target = row > 0 ? columns[column][row - 1] : index
            case .down: target = row + 1 < columns[column].count ? columns[column][row + 1] : index
            case .left: target = column > 0 ? columns[column - 1][min(row, columns[column - 1].count - 1)] : index
            case .right: target = column + 1 < columns.count ? columns[column + 1][min(row, columns[column + 1].count - 1)] : index
            }
        }
        return (0..<count).contains(target) ? target : index
    }

    /// How many columns an adaptive `LazyVGrid` makes: as many minimum-width columns as fit.
    static func adaptiveColumns(width: CGFloat, minimum: CGFloat, spacing: CGFloat, inset: CGFloat) -> Int {
        max(1, Int((width - 2 * inset + spacing) / (minimum + spacing)))
    }
}

/// How a keyboard grid learns its order: given, or worked out from its width like an adaptive grid.
enum GridLayout: Equatable {
    case order(GridOrder)
    case adaptive(minimum: CGFloat, spacing: CGFloat, inset: CGFloat)
}

/// One collection's highlight. Its own object, so moving the highlight re-renders the two items involved
/// rather than the page.
@MainActor
@Observable
final class GridKeyboard {
    let id = UUID()
    var highlighted: Int?
    var isFocused = false
    /// The item Space or Return last opened, with a serial so opening it again counts.
    var activated: (index: Int, serial: Int)?
    /// Items on screen, so the first arrow press starts where you're looking rather than at the top.
    @ObservationIgnored var visible = Set<Int>()
}

/// What an item needs to know: whether to draw the highlight (and keep its zoom probe), and when to open.
struct GridItemState: Equatable {
    var highlighted = false
    /// Changes to a new serial each time Space or Return opens this item.
    var activation: Int?
}

/// Lets the page's own scroll view bring a highlighted item into view, for element grids that grow
/// taller than the window inside a page.
@MainActor
@Observable
final class ScrollTarget {
    var id: AnyHashable?
}

struct GridCellID: Hashable {
    let grid: UUID
    let index: Int
}

extension EnvironmentValues {
    @Entry var gridKeyboard: GridKeyboard? = nil
    @Entry var gridItem = GridItemState()
    @Entry var pageScrollTarget: ScrollTarget? = nil
    /// The grid scrolls by its items' own `ForEach` ids, so items mustn't add one (see `keyboardGrid`).
    @Entry var gridItemsHaveIDs = false
}

extension View {
    /// Makes this collection one Tab stop with arrow-key navigation. Items mark themselves with
    /// `keyboardGridItem(_:)`.
    ///
    /// `id` gives the `ForEach` id of the item at an index, for scrolling to it. Pass it whenever items are
    /// identified by something other than their position: otherwise each item gets an `.id` of its
    /// position, which overrides the `ForEach` identity, and a lazy grid then kept stale tiles after a
    /// search changed which items it shows.
    func keyboardGrid(count: Int, layout: GridLayout, id: ((Int) -> AnyHashable)? = nil) -> some View {
        modifier(KeyboardGrid(count: count, layout: layout, itemID: id))
    }

    /// On a scroll view's content: keyboard grids inside it (which have no scroll view of their own, like an
    /// album page's track list) bring their highlighted item into view by scrolling this one.
    func followsKeyboardHighlight() -> some View {
        modifier(FollowsKeyboardHighlight())
    }

    func keyboardGridItem(_ index: Int) -> some View {
        modifier(KeyboardGridItem(index: index))
    }

    /// The keyboard highlight, drawn like a focus ring around an item's art or row.
    func keyboardHighlight(_ isOn: Bool, cornerRadius: CGFloat) -> some View {
        overlay {
            if isOn {
                RoundedRectangle(cornerRadius: cornerRadius + 4, style: .continuous)
                    .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                    .padding(-4)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct KeyboardGrid: ViewModifier {
    let count: Int
    let layout: GridLayout
    let itemID: ((Int) -> AnyHashable)?
    @State private var grid = GridKeyboard()
    @State private var width: CGFloat = 0
    @FocusState private var focused: Bool
    @Environment(\.pageScrollTarget) private var pageScroll
    @Environment(\.elementPreview) private var previewing

    private var order: GridOrder {
        switch layout {
        case .order(let order): order
        case .adaptive(let minimum, let spacing, let inset):
            .rows(columns: GridNavigation.adaptiveColumns(width: width, minimum: minimum, spacing: spacing, inset: inset))
        }
    }

    func body(content: Content) -> some View {
        if previewing {
            content
        } else {
            ScrollViewReader { proxy in
                content
                    .environment(\.gridKeyboard, grid)
                    .environment(\.gridItemsHaveIDs, itemID != nil)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                    // Keyboard only: a click opens the item under the pointer instead of focusing the grid.
                    .focusable(interactions: .activate)
                    .focused($focused)
                    .focusEffectDisabled()
                    .onChange(of: focused) { grid.isFocused = focused }
                    .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                        move(press.key)
                        return .handled
                    }
                    .onKeyPress(keys: [.space, .return]) { _ in
                        // Nothing highlighted: Space stays play/pause.
                        guard let index = grid.highlighted else { return .ignored }
                        grid.activated = (index, (grid.activated?.serial ?? 0) + 1)
                        return .handled
                    }
                    .onChange(of: grid.highlighted) { _, index in
                        guard let index, index < count else { return }
                        let id = itemID?(index) ?? AnyHashable(GridCellID(grid: grid.id, index: index))
                        withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id) }
                        pageScroll?.id = id
                    }
                    // A different set of items (search, filter): the old position means nothing.
                    .onChange(of: count) { grid.highlighted = nil }
            }
        }
    }

    private func move(_ key: KeyEquivalent) {
        guard count > 0 else { return }
        guard let current = grid.highlighted, current < count else {
            grid.highlighted = min(grid.visible.min() ?? 0, count - 1)
            return
        }
        let direction: GridMove = switch key {
        case .leftArrow: .left
        case .rightArrow: .right
        case .upArrow: .up
        default: .down
        }
        grid.highlighted = GridNavigation.move(direction, from: current, count: count, order: order)
    }
}

private struct FollowsKeyboardHighlight: ViewModifier {
    @State private var target = ScrollTarget()

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .environment(\.pageScrollTarget, target)
                .onChange(of: target.id) { _, id in
                    if let id { withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id) } }
                }
        }
    }
}

private struct KeyboardGridItem: ViewModifier {
    let index: Int
    @Environment(\.gridKeyboard) private var grid
    @Environment(\.gridItemsHaveIDs) private var haveIDs
    @Environment(\.scrollActivity) private var scrollActivity

    func body(content: Content) -> some View {
        if let grid {
            let item = content
                // On pages with shelves, items rather than the page skip hit-testing while it scrolls.
                .allowsHitTesting(!(scrollActivity?.isScrolling ?? false))
                .environment(\.gridItem, GridItemState(
                    highlighted: grid.isFocused && grid.highlighted == index,
                    activation: grid.activated?.index == index ? grid.activated?.serial : nil))
                .onAppear { grid.visible.insert(index) }
                .onDisappear { grid.visible.remove(index) }
            // Even `.id(nil)` would replace the ForEach identity, so it's left off entirely when not needed.
            if haveIDs {
                item
            } else {
                item.id(GridCellID(grid: grid.id, index: index))
            }
        } else {
            content
        }
    }
}
