import SwiftUI

/// The editor's Appearance tab: how the element is laid out on its page. Its name sits at the top of
/// the editor, and what it finds lives on the Rules tab.
struct FilterAppearanceForm: View {
    @Binding var draft: EditableFilter
    @Binding var appearance: ElementAppearance

    var body: some View {
        Form {
            Section("Layout") {
                Picker("Layout", selection: Binding(get: { appearance.layout }, set: { setLayout($0) })) {
                    ForEach(ElementAppearance.layouts(for: draft.output), id: \.self) { Text($0.title).tag($0) }
                }
                // Five layouts don't fit a phone's width as segments ("Cover F…"); a menu row does.
                #if os(macOS)
                .pickerStyle(.segmented)
                #else
                .pickerStyle(.menu)
                #endif
                .accessibilityIdentifier("editor.layout")
                Picker("Size", selection: $appearance.size) {
                    ForEach(ElementAppearance.Size.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(appearance.layout == .list)
                // Cover Flow is always one row; a timeline's rows live in its own section.
                if rowStepperRange.count > 1, appearance.layout != .timeline {
                    Stepper(value: $appearance.rows, in: rowStepperRange) {
                        LabeledContent(rowsLabel,
                                       value: appearance.rows == ElementAppearance.allRows ? "All" : "\(appearance.rows)")
                    }
                    .help(ElementAppearance.allowsAllRows(appearance.layout)
                          ? "All shows every item. A number limits the rows; the rest scroll sideways."
                          : "Rows that scroll sideways together.")
                }
                if appearance.layout == .list {
                    Stepper(value: $appearance.columns, in: ElementAppearance.columnRange) {
                        LabeledContent("Columns", value: "\(appearance.columns)")
                    }
                }
                // Only where it makes a difference: with one row (or one list column) both orders look the same.
                if appearance.fillApplies {
                    Picker("Fill", selection: Binding(get: { appearance.effectiveFill }, set: { appearance.setFill($0) })) {
                        Text("Across").tag(ElementAppearance.Fill.across)
                        Text("Down").tag(ElementAppearance.Fill.down)
                    }
                    .pickerStyle(.segmented)
                    .help("Across fills each row before the next; Down fills each column first. Grids and shelves default to Across, lists to Down.")
                }
            }

            if appearance.layout == .timeline {
                timelineSection
            }

            Section("Style") {
                Picker("Spacing", selection: $appearance.spacing) {
                    ForEach(ElementAppearance.Spacing.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Show header", isOn: $appearance.showHeader)
                Toggle("Show play buttons", isOn: $appearance.showPlayButtons)
                    .disabled(!appearance.showHeader)
                Toggle("Show footer", isOn: $appearance.showFooter)
                    .disabled(!footerApplies)
                    .help(footerApplies ? "The title under each tile; off shows the art alone."
                          : appearance.layout == .coverFlow ? "Cover Flow always shows the centre album's title under it."
                          : "Lists and songs show their text beside the art, so there's no footer to hide.")
                if !appearance.showHeader {
                    Text("Hidden headers: right-click the element, or use Edit Page, to change it later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                SortFieldPicker(title: appearance.layout == .timeline ? "Within a year" : "Order", selection: Binding(
                    get: { appearance.sortOverride?.field },
                    set: { setOverride($0) }
                ), allowsNone: true)
                if let key = appearance.sortOverride, let labels = SortKeysEditor.orderLabels(key.field) {
                    Picker("Direction", selection: Binding(
                        get: { key.ascending },
                        set: { appearance.sortOverride?.ascending = $0 }
                    )) {
                        Text(labels.descending).tag(false)
                        Text(labels.ascending).tag(true)
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Order")
            } footer: {
                Text(appearance.layout == .timeline
                     ? "Years always run in the order set above; this orders albums within each year (or leave it to the rules' sort)."
                     : "Reorders what the rules return, after every step. Which items appear doesn't change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Grids and lists start at All (shown as "All"); shelves always have at least one row.
    private var rowStepperRange: ClosedRange<Int> {
        let range = ElementAppearance.rowRange(layout: appearance.layout, output: draft.output)
        return ElementAppearance.allowsAllRows(appearance.layout) ? ElementAppearance.allRows...range.upperBound : range
    }

    /// The timeline's own settings: which way the years run, and how a busy year makes room.
    private var timelineSection: some View {
        Section {
            Picker("Years", selection: Binding(get: { appearance.timelineOrder ?? .oldestFirst },
                                               set: { appearance.timelineOrder = $0 == .oldestFirst ? nil : $0 })) {
                Text("Oldest first").tag(ElementAppearance.TimelineOrder.oldestFirst)
                Text("Newest first").tag(ElementAppearance.TimelineOrder.newestFirst)
            }
            .pickerStyle(.segmented)
            Picker("Busy years", selection: Binding(get: { appearance.timelineGrowth ?? .wider },
                                                    set: { appearance.timelineGrowth = $0 == .wider ? nil : $0 })) {
                Text("Grow wider").tag(ElementAppearance.TimelineGrowth.wider)
                Text("Grow taller").tag(ElementAppearance.TimelineGrowth.taller)
            }
            .pickerStyle(.segmented)
            if appearance.timelineGrowth == .taller {
                Stepper(value: Binding(get: { appearance.effectiveTimelineColumns }, set: { appearance.timelineColumns = $0 }),
                        in: ElementAppearance.timelineColumnRange) {
                    LabeledContent("Columns per year", value: "\(appearance.effectiveTimelineColumns)")
                }
            } else {
                Stepper(value: $appearance.rows, in: ElementAppearance.rowRange(layout: .timeline, output: draft.output)) {
                    LabeledContent("Rows per year", value: "\(appearance.rows)")
                }
            }
        } header: {
            Text("Timeline")
        } footer: {
            Text(appearance.timelineGrowth == .taller
                 ? "Each year is up to this many albums wide and grows downwards; quiet years shrink to fit."
                 : "Every year is the same height; busy years spread sideways.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var footerApplies: Bool {
        appearance.layout != .list && appearance.layout != .coverFlow && draft.output != .songs
    }

    private var rowsLabel: String {
        switch appearance.layout {
        case .list where appearance.columns > 1: "Rows per column"
        default: "Rows"
        }
    }

    private func setLayout(_ layout: ElementAppearance.Layout) {
        guard layout != appearance.layout else { return }
        appearance.layout = layout
        appearance.rows = ElementAppearance.defaultRows(layout: layout, output: draft.output)
    }

    private func setOverride(_ field: SortField?) {
        guard let field else { appearance.sortOverride = nil; return }
        guard field != appearance.sortOverride?.field else { return }
        // Text sorts read naturally A to Z; numbers and dates highest or newest first.
        let ascending = if case .field(let f) = field { f.type == .text } else { true }
        appearance.sortOverride = SortKey(field: field, ascending: ascending)
    }
}
