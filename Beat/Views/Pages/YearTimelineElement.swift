import SwiftUI

/// An album element as a timeline: years along a line that scrolls sideways, each year's albums as a small grid
/// under its mark, titles below the covers. Busy years grow wider (every year the same height) or, with a column
/// cap, taller; the years sit top-aligned either way. Within a year, albums keep the element's own order.
/// Named for years because SwiftUI already has a `TimelineView`.
struct YearTimelineElement<Cell: View>: View {
    @Environment(\.pageInset) private var pageInset
    let count: Int
    /// The item's year; 0 for none.
    let year: (Int) -> Int
    let newestFirst: Bool
    let rows: Int
    /// The most columns a year takes when years grow taller; nil keeps every year `rows` tall.
    let maxColumns: Int?
    let fill: ElementAppearance.Fill
    let tileWidth: CGFloat
    let spacing: CGFloat
    let rowSpacing: CGFloat
    /// Keeps the year labels' space but not their text: the loading placeholder has no years to show.
    var hidesYears = false
    @ViewBuilder let cell: (Int) -> Cell
    @Environment(\.elementPreview) private var previewing

    var body: some View {
        let groups = TimelineYears.group(count, year: year, newestFirst: newestFirst)
        // Each year's mini-grid, as columns of item indices.
        let laidOut = groups.map { group in
            TimelineYears.grid(count: group.indices.count, rows: rows, maxColumns: maxColumns, fill: fill)
                .map { $0.map { group.indices[$0] } }
        }
        ScrollView(.horizontal, showsIndicators: false) {
            // No spacing between years: each one's stretch of the line runs into the next. Years of differing
            // heights (growing taller) are all built up front, so the element's height doesn't jump when a
            // taller year scrolls into view; same-height years can be built as they appear.
            Group {
                if maxColumns == nil {
                    LazyHStack(alignment: .top, spacing: 0) { years(groups, laidOut) }
                } else {
                    HStack(alignment: .top, spacing: 0) { years(groups, laidOut) }
                }
            }
            .padding(.horizontal, pageInset)
            .padding(.vertical, 6)
        }
        // Arrow keys cross from one year's grid into the next.
        .keyboardGrid(count: count, layout: .order(.slots(laidOut.flatMap { $0 })))
    }

    private func years(_ groups: [(year: Int?, indices: [Int])], _ laidOut: [[[Int]]]) -> some View {
        ForEach(groups.indices, id: \.self) { g in
            VStack(alignment: .leading, spacing: 12) {
                mark(groups[g].year)
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(laidOut[g].indices, id: \.self) { column in
                        VStack(alignment: .leading, spacing: rowSpacing) {
                            ForEach(laidOut[g][column], id: \.self) {
                                cell($0).allowsHitTesting(!previewing).keyboardGridItem($0)
                            }
                        }
                        .frame(width: tileWidth, alignment: .top)
                    }
                }
                // The gap before the next year, kept under this year's stretch of the line.
                .padding(.trailing, spacing * 2.5)
            }
        }
    }

    /// The year, above its stretch of the line with a dot where the year begins.
    private func mark(_ year: Int?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(year.map(String.init) ?? "No year")
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .opacity(hidesYears ? 0 : 1)
            ZStack(alignment: .leading) {
                Rectangle().fill(.quaternary).frame(height: 2)
                Circle().fill(.secondary).frame(width: 8, height: 8)
            }
        }
    }
}
