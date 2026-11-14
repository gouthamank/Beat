import SwiftUI
import UIKit

/// The element editor on iPad and iPhone, as Apple's own editors are: one navigation stack, Cancel and Create (or
/// Save) in its bar, the rules as a form whose rules open their own pages. Footer buttons outside the stack stayed on
/// screen inside a rule, where Cancel read as undoing that rule. A phone switches between editing and the preview in
/// the bar; an iPad shows the preview beside the settings. Closing with changes asks first, from Cancel or a swipe.
struct ElementEditorLayout<Preview: View>: View {
    private enum EditorTab { case rules, appearance }

    @Binding var draft: EditableFilter
    @Binding var appearance: ElementAppearance
    let context: ElementEditorContext
    @ViewBuilder let preview: () -> Preview
    let save: () -> Void
    let cancel: () -> Void
    let delete: () -> Void
    @Environment(\.compactLayout) private var compact
    @State private var tab = EditorTab.rules
    @State private var showingPreview = false
    @State private var confirmingDiscard = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(draft.name.isEmpty ? "New Element" : draft.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { closeAsking() }
                            .accessibilityIdentifier("editor.cancel")
                            .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                                Button("Discard Changes", role: .destructive, action: cancel)
                                Button("Keep Editing", role: .cancel) {}
                            }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(context.saveTitle, action: save)
                            .disabled(!context.canSave)
                            .accessibilityIdentifier("editor.save")
                    }
                    if compact {
                        // In place of the title, which the form's name row shows anyway.
                        ToolbarItem(placement: .principal) {
                            Picker("Show", selection: $showingPreview) {
                                Text("Edit").tag(false)
                                Text("Preview").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }
        }
        .presentationSizing(.page)
        // A swipe down with changes asks too, rather than losing them.
        .interactiveDismissDisabled(context.hasChanges)
        .background { SheetDismissAttempt { confirmingDiscard = true } }
    }

    @ViewBuilder
    private var content: some View {
        if compact {
            if showingPreview {
                preview().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                settings
            }
        } else {
            HStack(spacing: 0) {
                preview().frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                settings.frame(width: 420)
            }
        }
    }

    private var settings: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $tab) {
                Text("Rules").tag(EditorTab.rules)
                Text("Appearance").tag(EditorTab.appearance)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            switch tab {
            case .rules:
                RulesForm(draft: $draft, nameCaption: context.nameCaption, delete: context.canDelete ? delete : nil)
            case .appearance:
                FilterAppearanceForm(draft: $draft, appearance: $appearance)
            }
        }
    }

    private func closeAsking() {
        if context.hasChanges { confirmingDiscard = true } else { cancel() }
    }
}

/// Hears a swipe down on a sheet that `interactiveDismissDisabled` holds open, so it can ask about the changes, as
/// Apple's editors do. SwiftUI has no hook for it: this joins the sheet's presentation controller delegate (SwiftUI's
/// own), adding only "did attempt to dismiss" and passing everything else on.
private struct SheetDismissAttempt: UIViewRepresentable {
    let onAttempt: () -> Void

    func makeUIView(context: Context) -> AttemptProbe { AttemptProbe() }

    func updateUIView(_ view: AttemptProbe, context: Context) {
        view.onAttempt = onAttempt
    }
}

final class AttemptProbe: UIView {
    var onAttempt: (() -> Void)?
    private var forwarder: DismissForwarder?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, forwarder == nil else { return }
        // After the sheet has finished presenting, when its controller and SwiftUI's delegate are in place.
        DispatchQueue.main.async { [weak self] in
            guard let self, let presentation = self.sheetController?.presentationController else { return }
            let forwarder = DismissForwarder(original: presentation.delegate) { [weak self] in self?.onAttempt?() }
            presentation.delegate = forwarder
            self.forwarder = forwarder
        }
    }

    /// The view controller the sheet presents: the outermost one above this view that something presented.
    private var sheetController: UIViewController? {
        let controllers = sequence(first: self as UIResponder, next: \.next).compactMap { $0 as? UIViewController }
        return controllers.last { $0.presentingViewController != nil }
    }
}

/// Answers "did attempt to dismiss" and forwards every other delegate call to the original delegate.
private final class DismissForwarder: NSObject, UIAdaptivePresentationControllerDelegate {
    /// Read from `responds(to:)` and `forwardingTarget(for:)`, which UIKit calls on the main thread.
    nonisolated(unsafe) private weak var original: UIAdaptivePresentationControllerDelegate?
    private let onAttempt: () -> Void

    init(original: UIAdaptivePresentationControllerDelegate?, onAttempt: @escaping () -> Void) {
        self.original = original
        self.onAttempt = onAttempt
    }

    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        onAttempt()
        original?.presentationControllerDidAttemptToDismiss?(presentationController)
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (original?.responds(to: selector) ?? false)
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }
}
