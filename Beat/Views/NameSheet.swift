import SwiftUI

/// Names a new or existing item: sidebar pages and folders, and page elements. A sheet rather than an
/// alert, because an alert's field can't preselect its text, and a new item's placeholder name should be
/// typed straight over.
struct NameSheet: View {
    let title: String
    let symbol: String
    /// "Rename", or "Create" for an item being added.
    let saveTitle: String
    /// Runs when the sheet closes without saving (Cancel, Esc, a swipe down): a new item is removed again.
    let cancel: (() -> Void)?
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool
    @State private var saved = false
    /// Only the first focus selects everything; tapping back into the field later puts the caret where you tap.
    @State private var selectedOnFocus = false

    init(title: String, symbol: String, name: String, saveTitle: String = "Rename", cancel: (() -> Void)? = nil,
         save: @escaping (String) -> Void) {
        self.title = title
        self.symbol = symbol
        self.saveTitle = saveTitle
        self.cancel = cancel
        self.save = save
        _name = State(initialValue: name)
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol)
                .font(.headline)
            TextField("Name", text: $name, selection: $selection)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(saveTitle, action: commit)
                    .keyboardShortcut(.defaultAction)
                    .beatGlassButtonStyle(prominent: true)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onDisappear { if !saved { cancel?() } }
        .onAppear { focused = true }
        // Select once focus has landed; taking focus resets the selection to a caret. On iOS focus lands only after
        // the sheet has slid up, well after `onAppear`, so selecting from there was undone.
        .onChange(of: focused) { _, on in
            guard on, !selectedOnFocus else { return }
            selectedOnFocus = true
            Task { @MainActor in selection = TextSelection(range: name.startIndex..<name.endIndex) }
        }
    }

    private func commit() {
        guard canSave else { return }
        saved = true
        save(name)
        dismiss()
    }
}
