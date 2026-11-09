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
                    ForEach(ElementAppearance.layouts(for: draft.output), id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Size", selection: $appearance.size) {
                    ForEach(ElementAppearance.Size.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(appearance.layout == .list)
                Stepper(value: $appearance.rows, in: rowStepperRange) {
                    LabeledContent(appearance.layout == .list && appearance.columns > 1 ? "Rows per column" : "Rows",
                                   value: appearance.rows == ElementAppearance.allRows ? "All" : "\(appearance.rows)")
                }
                .help(ElementAppearance.allowsAllRows(appearance.layout)
                      ? "All shows every item. A number limits the rows; the rest scroll sideways."
                      : "Rows that scroll sideways together.")
                if appearance.layout == .list {
                    Stepper(value: $appearance.columns, in: ElementAppearance.columnRange) {
                        LabeledContent("Columns", value: "\(appearance.columns)")
                    }
                }
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
                                        : "Lists and songs show their text beside the art, so there's no footer to hide.")
                if !appearance.showHeader {
                    Text("Hidden headers: right-click the element, or use Edit Page, to change it later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                SortFieldPicker(title: "Order", selection: Binding(
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
                Text("Reorders what the rules return, after every step. Which items appear doesn't change.")
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

    private var footerApplies: Bool { appearance.layout != .list && draft.output != .songs }

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
