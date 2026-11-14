import SwiftUI

/// Quick Open's search: the index (rebuilt in the background when the library or sidebar changes) and the results
/// for the current query, with the highlighted result.
@MainActor
@Observable
final class QuickOpenModel {
    var query = "" { didSet { if query != oldValue { search() } } }
    private(set) var groups: [QuickOpenGroup] = []
    /// The result Return opens: the first after each search, then moved with ↑ ↓ or the pointer.
    var selected: QuickOpenItem.Target?
    /// Set only when ↑ ↓ move the selection, so the list scrolls for the keyboard but not under the pointer.
    private(set) var scrollTarget: QuickOpenItem.Target?
    /// Whether the pointer has moved since the last results arrived. Until it does, rows don't take the highlight
    /// on hover: macOS hides the pointer while typing, and rows arriving under a resting pointer took the highlight
    /// from the top result, so Return opened something unseen.
    var pointerMoved = false

    private struct IndexKey: Equatable {
        let library: Int
        let tree: PageTree
        let libraryPages: [LibraryPage]
    }

    @ObservationIgnored private var indexKey: IndexKey?
    @ObservationIgnored private var index: Task<QuickOpenIndex, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    var items: [QuickOpenItem] { groups.flatMap(\.items) }

    /// Starts a fresh search, building the index first if the library or sidebar changed since the last one.
    func open(snapshot: LibrarySnapshot, version: Int, tree: PageTree, libraryPages: [LibraryPage]) {
        let key = IndexKey(library: version, tree: tree, libraryPages: libraryPages)
        if key != indexKey {
            indexKey = key
            index = Task.detached(priority: .userInitiated) {
                QuickOpenIndex(snapshot: snapshot, tree: tree, libraryPages: libraryPages)
            }
        }
        query = ""
        groups = []
        selected = nil
    }

    func move(_ step: Int) {
        let targets = items.map(\.target)
        guard !targets.isEmpty else { return }
        let current = selected.flatMap { targets.firstIndex(of: $0) } ?? (step > 0 ? -1 : targets.count)
        selected = targets[min(max(current + step, 0), targets.count - 1)]
        scrollTarget = selected
    }

    var selectedItem: QuickOpenItem? { items.first { $0.target == selected } }

    private func search() {
        searchTask?.cancel()
        let query = query
        guard let index else { return }
        searchTask = Task {
            let index = await index.value
            let groups = await Task.detached(priority: .userInitiated) { index.results(for: query) }.value
            guard !Task.isCancelled else { return }
            self.groups = groups
            selected = groups.first?.items.first?.target
            scrollTarget = nil
            pointerMoved = false
        }
    }
}

/// Quick Open (⌘K, or the sidebar's search button on iPad and iPhone): a panel over the window that finds pages,
/// albums, artists, genres and songs as you type. Return picks the highlighted result (always the top one until the
/// pointer moves), opening or playing songs and albums as set in Settings; ⌥Return does the other (Mac only).
/// Always in the window so the model, and its index, outlive each opening.
struct QuickOpenOverlay: View {
    @Environment(AppNavigator.self) private var navigator
    @Environment(LibraryStore.self) private var library
    @Environment(PageStore.self) private var pages
    @Environment(PlaybackQueue.self) private var queue
    @Environment(\.compactLayout) private var compact
    @AppStorage(LibraryPage.hiddenKey) private var hiddenLibraryPages = ""
    @AppStorage(QuickOpenSongAction.key) private var songAction = QuickOpenSongAction.album
    @AppStorage(QuickOpenAlbumAction.key) private var albumAction = QuickOpenAlbumAction.open
    @State private var model = QuickOpenModel()
    @State private var resultsHeight: CGFloat = 0
    /// Where the pointer was last seen over the panel, to tell a real move from rows changing under it.
    @State private var pointer: CGPoint?
    @FocusState private var fieldFocused: Bool

    private static let dimming = 0.3

    var body: some View {
        ZStack(alignment: .top) {
            if navigator.showingQuickOpen {
                Color.black.opacity(Self.dimming)
                    // The Mac's title bar has its own dim (`titleBarDim`): reaching under it too darkened the toolbar twice.
                    #if os(macOS)
                    .ignoresSafeArea(edges: [.horizontal, .bottom])
                    #else
                    .ignoresSafeArea()
                    #endif
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .transition(.opacity)
                panel
                    .padding(.top, compact ? 8 : 64)
                    .padding(.horizontal, compact ? 16 : 0)
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .animation(.snappy(duration: 0.2), value: navigator.showingQuickOpen)
        .titleBarDim(navigator.showingQuickOpen, opacity: Self.dimming) { close() }
        .onChange(of: navigator.showingQuickOpen) { _, showing in
            guard showing else { return }
            model.open(snapshot: library.snapshot, version: library.version, tree: pages.tree,
                       libraryPages: LibraryPage.available.filter { !LibraryPage.hidden(in: hiddenLibraryPages).contains($0) })
            // A frame later: the field isn't in the window yet in this update.
            Task { fieldFocused = true }
        }
    }

    private var panel: some View {
        VStack(spacing: 0) {
            field
            if !model.groups.isEmpty {
                Divider()
                results
            }
        }
        .frame(width: compact ? nil : 580)
        .frame(maxWidth: compact ? .infinity : nil)
        .beatGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        // The panel's own coordinates: rows moving under a resting pointer leave its location here unchanged.
        .onContinuousHover { phase in
            guard case .active(let location) = phase else { pointer = nil; return }
            if let pointer, pointer != location { model.pointerMoved = true }
            pointer = location
        }
        .accessibilityIdentifier("quickOpen")
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(.secondary)
            TextField("Pages, albums, artists, genres and songs", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($fieldFocused)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .submitLabel(.go)
                .onSubmit { pick(model.selectedItem, alternate: false) }
                .onKeyPress(.upArrow) { model.move(-1); return .handled }
                .onKeyPress(.downArrow) { model.move(1); return .handled }
                .onKeyPress(.escape) { close(); return .handled }
                #if os(macOS)
                // The other of opening and playing. Mac only: iPad and iPhone keep to one action per result.
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.option) else { return .ignored }
                    pick(model.selectedItem, alternate: true)
                    return .handled
                }
                #endif
                .accessibilityIdentifier("quickOpen.field")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(model.groups) { group in
                        Text(group.kind.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.top, group.kind == model.groups.first?.kind ? 2 : 10)
                            .padding(.bottom, 2)
                        ForEach(group.items) { item in
                            row(item).id(item.target)
                        }
                    }
                }
                .padding(8)
            }
            // As tall as the results, up to a limit, rather than always the limit.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, height in
                resultsHeight = height
            }
            .frame(height: min(max(resultsHeight, 44), compact ? 340 : 440))
            .onChange(of: model.scrollTarget) { _, target in
                if let target { proxy.scrollTo(target) }
            }
        }
    }

    private func row(_ item: QuickOpenItem) -> some View {
        let selected = model.selected == item.target
        return Button { pick(item, alternate: false) } label: {
            HStack(spacing: 10) {
                icon(item)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).lineLimit(1)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? AnyShapeStyle(Color.accentColor.opacity(0.22)) : AnyShapeStyle(.clear),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Typing stays in the field; ↑ ↓ move the highlight.
        .focusable(false)
        .onHover { if $0, model.pointerMoved { model.selected = item.target } }
    }

    @ViewBuilder
    private func icon(_ item: QuickOpenItem) -> some View {
        switch item.target {
        case .album(let id), .song(_, let id):
            ArtworkView(albumID: id, cornerRadius: 4)
        case .artist:
            symbol("music.microphone")
        case .genre:
            symbol("guitars")
        case .sidebar:
            symbol(item.symbol ?? "rectangle.grid.1x2")
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func close() {
        navigator.showingQuickOpen = false
    }

    /// Does what Settings ▸ General ▸ Quick Open says for songs and albums (`alternate`, ⌥Return, the other of opening
    /// and playing). Pages opened on a Library page wait briefly for cover colours, as tiles do.
    private func pick(_ item: QuickOpenItem?, alternate: Bool) {
        guard let item else { return }
        close()
        let snapshot = library.snapshot
        let hidden = LibraryPage.hidden(in: hiddenLibraryPages)
        switch QuickOpenAction.resolve(item.target, song: songAction, album: albumAction, alternate: alternate) {
        case .select(let sidebarItem):
            if case .page(let id) = sidebarItem { navigator.expandedFolders.formUnion(pages.tree.ancestors(of: id)) }
            navigator.selection = sidebarItem
        case .go(let route, let page, let track):
            navigator.openWhenReady(route) { navigator.goTo(route, in: page, hidden: hidden, highlighting: track) }
        case .showInSongs(let id, let albumID):
            let words = SearchText.words(navigator.searches[.songs] ?? "")
            let text = snapshot.trackSearchText[id] ?? snapshot.tracksByID[id].map(SongsQuery.searchText) ?? ""
            navigator.showInSongs(id, album: albumID, hidden: hidden,
                                  clearingSearch: !words.isEmpty && !SearchText.matches(text, words))
        case .playAlbum(let albumID, let from):
            guard let album = snapshot.albumsByID[albumID] else { return }
            let tracks = snapshot.tracks(of: album)
            queue.play(tracks, startAt: from.flatMap { id in tracks.firstIndex { $0.id == id } } ?? 0)
        }
    }
}
