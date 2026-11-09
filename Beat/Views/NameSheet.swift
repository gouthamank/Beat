import SwiftUI

/// Names a new or existing item: sidebar pages and folders, and page elements. A sheet rather than an
/// alert, because an alert's field can't preselect its text, and a new item's placeholder name should be
/// typed straight over.
struct NameSheet: View {
    let title: String
    let symbol: String
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selection: TextSelection?
    @FocusState private var focused: Bool

    init(title: String, symbol: String, name: String, save: @escaping (String) -> Void) {
        self.title = title
        self.symbol = symbol
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
                .focused($focused)
                .onSubmit(commit)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: commit)
                    .keyboardShortcut(.defaultAction)
                    .beatGlassButtonStyle(prominent: true)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 320)
        .onAppear {
            focused = true
            // Select after focus lands; taking focus would otherwise reset the selection to a caret.
            Task { @MainActor in selection = TextSelection(range: name.startIndex..<name.endIndex) }
        }
    }

    private func commit() {
        guard canSave else { return }
        save(name)
        dismiss()
    }
}
