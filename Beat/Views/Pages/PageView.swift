import SwiftUI

/// A user page: its elements top to bottom. Home is one of these.
struct PageView: View {
    let pageID: UUID
    @Environment(PageStore.self) private var pages
    @Environment(AppNavigator.self) private var navigator
    @State private var editing = false
    @State private var pendingDelete: PageElement?
    @State private var scrolling = ScrollActivity()
    /// Brings a keyboard-highlighted item into view when its element is taller than the window.
    @State private var scrollTarget = ScrollTarget()

    var body: some View {
        if let node = pages.node(pageID), let page = node.page {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(page.elements) { element in
                            ElementView(element: element, pageID: pageID, result: pages.results[element.id],
                                        editing: editing, delete: { pendingDelete = element })
                        }
                    }
                    .padding(.vertical, 24)
                    // Items pause themselves (see KeyboardGridItem); the shelves' own scroll views must stay live.
                    .environment(\.scrollActivity, scrolling)
                }
                .tracksScrolling(scrolling)
                .remembersScroll(.page(pageID))
                // The page column's content, for UI tests that check the now-playing bar sits over it.
                .accessibilityIdentifier("page.\(node.name)")
                .onChange(of: scrollTarget.id) { _, id in
                    if let id { withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id) } }
                }
            }
            .environment(\.pageScrollTarget, scrollTarget)
            .overlay {
                if page.elements.isEmpty {
                    ContentUnavailableView {
                        Label("This Page Is Empty", systemImage: node.symbol)
                    } description: {
                        Text("Add elements, each with its own smart filter and layout.")
                    } actions: {
                        Button("Add Element") { navigator.newElement(on: pageID, customFields: pages.customFields) }.beatGlassButtonStyle(prominent: true)
                    }
                }
            }
            .navigationTitle(node.name)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Add Element", systemImage: "plus") { navigator.newElement(on: pageID, customFields: pages.customFields) }
                        .accessibilityIdentifier("page.addElement")
                    Toggle(isOn: $editing.animation(.snappy)) {
                        Label("Edit Page", systemImage: "square.and.pencil")
                    }
                    .help(editing ? "Done Editing" : "Edit Page")
                    .disabled(page.elements.isEmpty)
                }
            }
            .confirmationDialog("Delete “\(pendingDelete?.filter.name ?? "")”?", isPresented: Binding(
                get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let element = pendingDelete { pages.deleteElement(element.id, from: pageID) }
                }
            } message: {
                Text("Its smart filter is deleted with it.")
            }
            .modifier(PageEvaluation(pageID: pageID))
        } else {
            ContentUnavailableView("Page Not Found", systemImage: "questionmark.folder")
        }
    }
}

/// One element's full result, opened from its header ("See All").
struct ElementDetailView: View {
    let route: ElementRoute
    @Environment(PageStore.self) private var pages
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        if let element = pages.element(route.elementID, on: route.pageID) {
            Group {
                if let result = pages.results[element.id] {
                    content(element.filter.name, result)
                        .toolbar {
                            PlayShuffleToolbar(tracks: result.tracks)
                            ToolbarItem(placement: .primaryAction) {
                                Button("Edit", systemImage: "slider.horizontal.3") { navigator.edit(element, on: route.pageID) }
                                    .help("Edit Element")
                            }
                        }
                } else {
                    ProgressView().navigationTitle(element.filter.name)
                }
            }
            .modifier(PageEvaluation(pageID: route.pageID))
        } else {
            ContentUnavailableView("Element Not Found", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    @ViewBuilder
    private func content(_ title: String, _ result: FilterResult) -> some View {
        switch result.kind {
        case .songs: SongsTableView(title: title, tracks: result.tracks)
        case .albums: AlbumGridView(title: title, albums: result.albums)
        case .artists: ArtistGridView(title: title, artists: result.artists)
        case .genres: GenreGridView(title: title, genres: result.genres)
        }
    }
}

/// Re-evaluates a page's elements whenever the library, play history or the page itself changes.
private struct PageEvaluation: ViewModifier {
    let pageID: UUID
    @Environment(PageStore.self) private var pages
    @Environment(LibraryStore.self) private var library
    @Environment(PlayHistoryStore.self) private var history

    private struct Key: Equatable {
        let library: PageStore.LibraryKey
        let page: Page?
    }

    func body(content: Content) -> some View {
        let key = PageStore.LibraryKey(library: library.version, history: history.version)
        content.task(id: Key(library: key, page: pages.node(pageID)?.page)) {
            // Debounce bursts (e.g. several plays or edits in a row), but not a first look: an element with no
            // results yet shows a placeholder, and waiting only delayed it.
            let elements = pages.node(pageID)?.page?.elements ?? []
            if elements.allSatisfy({ pages.results[$0.id] != nil }) {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
            }
            await pages.evaluate(pageID: pageID, snapshot: library.snapshot, history: history.stats, key: key)
        }
    }
}
