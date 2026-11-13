import SwiftUI

/// How the sidebar follows an album page's cover colours (Settings ▸ Appearance).
enum SidebarTint: String, CaseIterable {
    case off, subtle, full

    static let key = "appearance.sidebarTint"

    var title: String {
        switch self {
        case .off: "Off"
        case .subtle: "Subtle"
        case .full: "Full"
        }
    }
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    @Environment(PageStore.self) private var pages
    @Environment(AppNavigator.self) private var navigator
    @State private var pendingDelete: SidebarNode?
    @State private var iconTarget: SidebarNode?
    @State private var dropTargetingTopLevel = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.compactLayout) private var compact
    @AppStorage(LibraryPage.hiddenKey) private var hiddenLibraryPages = ""
    @AppStorage(SidebarTint.key) private var tintSetting = SidebarTint.full.rawValue

    /// The album page's colours, when the sidebar should take them.
    private var tint: (palette: ArtworkPalette, style: SidebarTint)? {
        // Not as a phone's glass drawer, which shows the album page itself through it.
        guard !compact, let style = SidebarTint(rawValue: tintSetting), style != .off,
              let palette = navigator.coverTint.current?.palette else { return nil }
        return (palette, style)
    }

    var body: some View {
        List(selection: $selection) {
            SidebarTree(rows: SidebarRow.visible(pages.tree.nodes, expanded: navigator.expandedFolders), actions: actions)

            let library = LibraryPage.allCases.filter { !LibraryPage.hidden(in: hiddenLibraryPages).contains($0) }
            if !library.isEmpty {
                Section("Library") {
                    ForEach(library) { page in
                        Label(page.title, systemImage: page.symbol).tag(page.item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { navigator.showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            }
        }
        #endif
        // On album pages the sidebar takes the cover's colours, so the window reads as one surface.
        .scrollContentBackground(tint == nil && !compact ? .automatic : .hidden)
        .background {
            if let tint, let albumID = navigator.coverTint.current?.albumID {
                // The same window-sized backdrop as the album page, so its blur carries on into the sidebar.
                WindowAlignedAlbumBackground(albumID: albumID, palette: tint.palette)
                    .opacity(tint.style == .full ? 1 : 0.35)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .environment(\.colorScheme, tint?.style == .full ? (tint!.palette.isDark ? .dark : .light) : colorScheme)
        .animation(Motion.fade, value: navigator.coverTint.current?.albumID)
        .animation(Motion.fade, value: tintSetting)
        .sheet(item: Binding(
            get: { navigator.renaming.flatMap { pages.node($0) } },
            set: { if $0 == nil { navigator.renaming = nil } }
        )) { node in
            let isNew = navigator.namingNew?.id == node.id
            NameSheet(
                title: isNew ? (node.isFolder ? "New Folder" : "New Page") : (node.isFolder ? "Folder Name" : "Page Name"),
                symbol: node.symbol, name: node.name, saveTitle: isNew ? "Create" : "Rename",
                // A new item that isn't named (Cancel, Esc, a swipe down) isn't kept.
                cancel: isNew ? { navigator.cancelNaming(in: pages) } : nil
            ) {
                pages.rename(node.id, to: $0)
                if isNew { navigator.namingNew = nil }
            }
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let node = pendingDelete { pages.delete(node.id) }
            }
        } message: {
            Text(deleteMessage)
        }
        // Presented from here rather than from each row: per-row popovers wrap the row and break selection.
        .sheet(item: $iconTarget) { node in
            SymbolPicker(symbol: Binding(get: { pages.node(node.id)?.symbol ?? node.symbol }, set: { pages.setSymbol(node.id, $0) })) {
                iconTarget = nil
            }
            .padding(16)
        }
    }

    private var actions: SidebarActions {
        SidebarActions(
            delete: { pendingDelete = $0 },
            chooseIcon: { iconTarget = $0 },
            expand: { navigator.expandedFolders.insert($0) },
            toggle: { id in
                if navigator.expandedFolders.contains(id) { navigator.expandedFolders.remove(id) } else { navigator.expandedFolders.insert(id) }
            }
        )
    }

    /// New Page / New Folder at the top level. Also a drop target for moving items out to the top level.
    private var bottomBar: some View {
        Menu {
            Button("New Page", systemImage: "rectangle.grid.1x2") { create(folder: false) }
            Button("New Folder", systemImage: "folder") { create(folder: true) }
            Divider()
            Button("Add Default Home Page", systemImage: "house") {
                let home = Presets.homePage()
                pages.insert(home, into: nil, at: 0)
                selection = .page(home.id)
            }
        } label: {
            Label(dropTargetingTopLevel ? "Move to Top Level" : "New", systemImage: dropTargetingTopLevel ? "arrow.up.to.line" : "plus.circle")
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .foregroundStyle(dropTargetingTopLevel ? Color.accentColor : .secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            return pages.move(id, into: nil)
        } isTargeted: { dropTargetingTopLevel = $0 }
    }

    private func create(folder: Bool) {
        let previous = navigator.selection
        let id = pages.create(folder: folder, in: nil)
        navigator.nameNew(id, folder: folder, previousSelection: previous)
    }

    private var deleteTitle: String {
        "Delete “\(pendingDelete?.name ?? "")”?"
    }

    private var deleteMessage: String {
        guard let node = pendingDelete else { return "" }
        guard node.isFolder else { return "Its elements and their smart filters are deleted with it." }
        let count = pages.tree.pageCount(in: node.id)
        return switch count {
        case 0: "The folder is empty."
        case 1: "The folder and the 1 page inside it are deleted."
        default: "The folder and the \(count) pages inside it are deleted."
        }
    }
}

/// Sidebar-level state the rows reach through closures, so rows stay plain List rows.
private struct SidebarActions {
    let delete: (SidebarNode) -> Void
    let chooseIcon: (SidebarNode) -> Void
    let expand: (UUID) -> Void
    let toggle: (UUID) -> Void
}

/// A visible row of the tree: a node plus where it sits, so a flat drop index maps back to a tree position.
private struct SidebarRow: Identifiable {
    let node: SidebarNode
    let depth: Int
    let parent: UUID?
    let index: Int
    let isExpanded: Bool
    /// The "Add" line closing an open folder; `node` is that folder. A drop just above it lands at the folder's end.
    var isAddRow = false

    var id: String { isAddRow ? "add-\(node.id)" : node.id.uuidString }

    /// Depth-first rows, skipping the contents of collapsed folders. Every open folder ends with an Add row.
    static func visible(_ nodes: [SidebarNode], expanded: Set<UUID>) -> [SidebarRow] {
        var rows: [SidebarRow] = []
        func walk(_ nodes: [SidebarNode], depth: Int, parent: UUID?) {
            for (i, node) in nodes.enumerated() {
                let open = expanded.contains(node.id)
                rows.append(SidebarRow(node: node, depth: depth, parent: parent, index: i, isExpanded: open))
                guard open, let children = node.children else { continue }
                walk(children, depth: depth + 1, parent: node.id)
                rows.append(SidebarRow(node: node, depth: depth + 1, parent: node.id, index: children.count, isExpanded: false, isAddRow: true))
            }
        }
        walk(nodes, depth: 0, parent: nil)
        return rows
    }
}

/// The tree as one flat list with hand-drawn indentation. Nested `DisclosureGroup`s with their own
/// drop targets crash SwiftUI's outline drop handling on macOS, and a single `ForEach` avoids it.
/// Page rows carry only a tag, drag and a context menu: anything layered on a selectable row
/// (a drop target, a popover) swallows the click.
private struct SidebarTree: View {
    let rows: [SidebarRow]
    let actions: SidebarActions
    @Environment(PageStore.self) private var pages

    var body: some View {
        ForEach(rows) { row in
            if row.isAddRow {
                // Untagged, so it can't be selected; a click opens the folder-or-page menu.
                HStack(spacing: 0) {
                    Color.clear.frame(width: SidebarRow.indent(row.depth) + SidebarRow.chevronWidth, height: 1)
                    Menu {
                        NodeMenu(node: row.node, actions: actions, createOnly: true)
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .foregroundStyle(.secondary)
                    .help("Add a page or folder to “\(row.node.name)”")
                }
            } else if row.node.isFolder {
                FolderRow(row: row, actions: actions)
            } else {
                HStack(spacing: 0) {
                    Color.clear.frame(width: SidebarRow.indent(row.depth) + SidebarRow.chevronWidth, height: 1)
                    Label(row.node.name, systemImage: row.node.symbol)
                }
                .itemProvider { NSItemProvider(object: row.node.id.uuidString as NSString) }
                .contextMenu { NodeMenu(node: row.node, actions: actions) }
                .tag(SidebarItem.page(row.node.id))
            }
        }
        // A drop before row i lands at that row's level and position; past the last row, at the end of the top level.
        .dropDestination(for: String.self) { items, index in
            guard let id = items.first.flatMap(UUID.init(uuidString:)) else { return }
            let target = rows.indices.contains(index) ? rows[index] : nil
            // Applied after AppKit's drop callback returns; changing the list inside it trips SwiftUI's bookkeeping.
            Task { @MainActor in
                if let target { pages.move(id, into: target.parent, at: target.index) } else { pages.move(id, into: nil) }
            }
        }
    }
}

extension SidebarRow {
    /// The disclosure chevron's column. Wider on iPad and iPhone, whose list icons are larger and sat right against it.
    #if os(macOS)
    static let chevronWidth: CGFloat = 14
    #else
    static let chevronWidth: CGFloat = 24
    #endif
    static func indent(_ depth: Int) -> CGFloat { CGFloat(depth) * 14 }
}

/// Folders aren't selectable, so they can safely take a drop target ("move inside") and a click (expand/collapse).
private struct FolderRow: View {
    let row: SidebarRow
    let actions: SidebarActions
    @Environment(PageStore.self) private var pages
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: SidebarRow.indent(row.depth), height: 1)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                .frame(width: SidebarRow.chevronWidth)
            Label(row.node.name, systemImage: row.node.symbol)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy) { actions.toggle(row.node.id) } }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 2).padding(-3)
            }
        }
        .itemProvider { NSItemProvider(object: row.node.id.uuidString as NSString) }
        .dropDestination(for: String.self) { items, _ in
            guard let id = items.first.flatMap(UUID.init(uuidString:)), id != row.node.id else { return false }
            let folder = row.node.id
            Task { @MainActor in
                if pages.move(id, into: folder) { actions.expand(folder) }
            }
            return true
        } isTargeted: { dropTargeted = $0 }
        .contextMenu { NodeMenu(node: row.node, actions: actions) }
    }
}

private struct NodeMenu: View {
    let node: SidebarNode
    let actions: SidebarActions
    /// Only the "create inside" items, for a folder's Add row.
    var createOnly = false
    @Environment(PageStore.self) private var pages
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        if node.isFolder {
            Button("New Page", systemImage: "rectangle.grid.1x2") { create(folder: false, inside: true) }
            Button("New Folder", systemImage: "folder") { create(folder: true, inside: true) }
        } else {
            Button("New Page Below", systemImage: "rectangle.grid.1x2") { create(folder: false, inside: false) }
            Button("New Folder Below", systemImage: "folder") { create(folder: true, inside: false) }
        }
        if !createOnly { fullMenu }
    }

    @ViewBuilder
    private var fullMenu: some View {
        Divider()
        Button("Rename…", systemImage: "pencil") { navigator.renaming = node.id }
        Button("Change Icon…", systemImage: "face.smiling") { actions.chooseIcon(node) }
        Button("Duplicate", systemImage: "plus.square.on.square") { pages.duplicate(node.id) }
        moveMenu
        Divider()
        Button("Delete…", systemImage: "trash", role: .destructive) { actions.delete(node) }
    }

    private var moveMenu: some View {
        let parent = pages.tree.location(of: node.id)?.parent
        return Menu("Move To", systemImage: "folder.badge.gearshape") {
            Button("Top Level") { pages.move(node.id, into: nil) }
                .disabled(parent == nil)
            let folders = pages.tree.folders.filter { !pages.tree.isWithin($0.node.id, node.id) }
            if !folders.isEmpty { Divider() }
            ForEach(folders, id: \.node.id) { folder in
                Button(String(repeating: "    ", count: folder.depth) + folder.node.name) {
                    if pages.move(node.id, into: folder.node.id) { actions.expand(folder.node.id) }
                }
                .disabled(folder.node.id == parent)
            }
        }
    }

    private func create(folder: Bool, inside: Bool) {
        let previous = navigator.selection
        let id = inside ? pages.create(folder: folder, in: node.id) : pages.create(folder: folder, below: node.id)
        // Expand the folder so the new item is visible.
        if inside { actions.expand(node.id) }
        navigator.nameNew(id, folder: folder, previousSelection: previous)
    }
}
