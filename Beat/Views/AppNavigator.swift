import Observation
import SwiftUI

/// What the element editor saves to: an element on a page, or the defaults new elements start from.
enum EditorTarget: Hashable {
    case page(UUID)
    case defaults
}

/// An element being created or edited, and where it's saved.
struct ElementDraft: Identifiable, Hashable {
    var target: EditorTarget
    var filter: EditableFilter
    var appearance: ElementAppearance

    var id: UUID { filter.id }

    init(target: EditorTarget, element: PageElement) {
        self.target = target
        filter = EditableFilter(element.filter)
        appearance = element.appearance
    }
}

/// A page pushed in the detail column. Typed (rather than a `NavigationPath`) so going back can tell
/// which page left, for the album cover's flight home.
enum Route: Hashable {
    case album(PersistentID)
    case artist(String)
    case genre(String)
    case element(ElementRoute)
}

struct ScrollToTopRequest: Equatable {
    let item: SidebarItem
    let token: Int
}

/// A page element, for prompts presented away from its page (e.g. Rename).
struct ElementRef: Identifiable, Hashable {
    let pageID: UUID
    let elementID: UUID

    var id: UUID { elementID }
}

/// App-wide UI state that menus, the sidebar and sheets all need to reach.
@MainActor
@Observable
final class AppNavigator {
    var selection: SidebarItem? {
        // Each sidebar item keeps its own pushed pages while Beat runs, and the selection survives relaunch.
        didSet {
            guard selection != oldValue else { return }
            if let oldValue { savedPaths[oldValue] = path }
            switchingPages = true
            // One write per frame: SwiftUI rejects a stack path updated twice in one frame
            // ("NavigationAuthority bound path tried to update multiple times per frame").
            path = selection.flatMap { savedPaths[$0] } ?? []
            switchingPages = false
            UserDefaults.standard.set(selection?.storageString, forKey: Self.selectionKey)
        }
    }
    /// The detail column's pushed pages (albums, artists, See All…).
    var path: [Route] = [] {
        didSet {
            albumPageLeftFront(old: oldValue)
            coverTint.show(path.last)
        }
    }
    @ObservationIgnored private var savedPaths: [SidebarItem: [Route]] = [:]
    /// Set while a sidebar switch swaps in another page's path, which isn't going back.
    @ObservationIgnored private var switchingPages = false
    /// For the album cover's flight back into its tile when an album page is popped.
    @ObservationIgnored weak var hero: HeroTransition?
    /// Each sidebar page's search text, kept while Beat runs.
    var searches: [SidebarItem: String] = [:]
    /// Each sidebar page's scroll offset, kept while Beat runs. Not observed: only read when a page appears.
    @ObservationIgnored var scrollOffsets: [SidebarItem: CGFloat] = [:]
    /// Bumped when the selected sidebar page is clicked again at its top level; that page scrolls to the top.
    var scrollToTop: ScrollToTopRequest?
    /// Library ▸ Albums' artist list selection, kept while Beat runs.
    var albumArtistFilter = AlbumArtistFilter.all
    /// The front album or artist page's cover colours: the only source for the page, sidebar, window and bar.
    let coverTint = CoverTint()
    /// How far a trackpad swipe back has gone, 0...1, for the back chevron; 0 when no swipe is under way.
    var swipeProgress: CGFloat = 0
    /// Open sidebar folders, saved so the sidebar reopens the way it was left.
    var expandedFolders: Set<UUID> = AppNavigator.savedExpandedFolders() {
        didSet {
            UserDefaults.standard.set(expandedFolders.map(\.uuidString).sorted().joined(separator: ","), forKey: Self.expandedKey)
        }
    }
    /// The full Now Playing view, expanded over the window.
    var showingNowPlaying = false
    /// The now-playing bar's frame, read when Now Playing opens and closes so it can morph from and to it.
    @ObservationIgnored var barProbe: FrameProbe?
    /// The cover shown full-window, opened from an album page's header.
    var artViewer: ArtViewerRequest?
    /// The element being created or edited, if the editor is open.
    var editing: ElementDraft?
    /// The sidebar node whose rename prompt is showing.
    var renaming: UUID?
    /// The page element whose rename prompt is showing.
    var renamingElement: ElementRef?

    func openAlbum(_ id: PersistentID) { open(.album(id)) }
    func openArtist(_ id: String) { open(.artist(id)) }
    func openGenre(_ id: String) { open(.genre(id)) }

    /// Set while a tile waits for its page's colours before opening, so a second click doesn't open it twice.
    @ObservationIgnored private var preparingOpen = false

    /// Opens a page from a tile once its cover colours are ready (briefly; see `CoverTint.prepare`), so it
    /// expands already coloured instead of colouring in afterwards.
    func openWhenReady(_ route: Route, open: @escaping () -> Void) {
        guard !preparingOpen else { return }
        preparingOpen = true
        Task {
            // A frame or two for a probe the click just added to be placed in the window (see AlbumTile).
            try? await Task.sleep(for: .milliseconds(33))
            await coverTint.prepare(route)
            preparingOpen = false
            open()
        }
    }

    /// Pages that belong to the current page, like an element's See All.
    func push(_ route: Route) { path.append(route) }

    var canGoBack: Bool { !path.isEmpty }


    /// The path for one sidebar page's stack. A stack being torn down after a sidebar switch clears its
    /// path on the way out; tied to its own item, that write is ignored instead of wiping the new page's.
    func pathBinding(for item: SidebarItem?) -> Binding<[Route]> {
        Binding(
            get: { self.selection == item ? self.path : [] },
            set: { if self.selection == item { self.path = $0 } }
        )
    }

    func goBack() {
        guard canGoBack else { return }
        path.removeLast()
    }

    /// The selected sidebar page was clicked again: back to its top level, or, already there, to its top.
    func reselect() {
        if canGoBack {
            path = []
        } else if let selection {
            requestScrollToTop(selection)
        }
    }

    func requestScrollToTop(_ item: SidebarItem) {
        scrollToTop = ScrollToTopRequest(item: item, token: (scrollToTop?.token ?? 0) + 1)
    }

    /// Details drill down inside the page you started from (Artists ▸ Artist ▸ Album, Songs ▸ Artist ▸
    /// Album, Home ▸ Album ▸ Artist), so you stay where you were browsing. A page already in the trail
    /// is returned to rather than stacked again: Artist ▸ Album ▸ (that) Artist goes back to the first
    /// Artist, so trails never grow by repetition.
    nonisolated static func opening(_ route: Route, on path: [Route]) -> [Route] {
        if let i = path.firstIndex(of: route) { return Array(path.prefix(i + 1)) }
        return path + [route]
    }

    private func open(_ route: Route) {
        let next = Self.opening(route, on: path)
        if next != path { path = next }
    }

    /// An album or artist page that stops being the front page fades its colours out; going back from it
    /// (any way: back button, ⌘[, swipe, sidebar click) also flies its art home. Runs before SwiftUI removes
    /// the page, so it can still be measured.
    private func albumPageLeftFront(old: [Route]) {
        guard path.last != old.last else { return }
        let subject: HeroSubject
        switch old.last {
        case .album(let id)?: subject = .album(id)
        case .artist(let id)?: subject = .artist(id)
        default: return
        }
        hero?.fadeBackdrop(subject)
        if !switchingPages, path.count < old.count, Array(old.prefix(path.count)) == path {
            hero?.returnFlight(subject)
        }
    }

    // MARK: Restoring the sidebar

    static let selectionKey = "sidebar.selection"
    static let expandedKey = "sidebar.expanded"

    private static func savedExpandedFolders() -> Set<UUID> {
        let saved = UserDefaults.standard.string(forKey: expandedKey) ?? ""
        return Set(saved.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    /// Selects the page saved at the last quit, if it still exists and isn't hidden, opening the folders
    /// around it. Returns false when there's nothing to restore.
    func restoreSavedSelection(tree: PageTree, hidden: Set<LibraryPage>) -> Bool {
        // Deleted folders would otherwise linger in the saved list forever.
        expandedFolders.formIntersection(tree.folders.map(\.node.id))
        guard let saved = UserDefaults.standard.string(forKey: Self.selectionKey).flatMap(SidebarItem.init(storageString:))
        else { return false }
        switch saved {
        case .page(let id):
            guard tree.node(id)?.page != nil else { return false }
            expandedFolders.formUnion(tree.ancestors(of: id))
        default:
            guard let library = LibraryPage(saved), !hidden.contains(library) else { return false }
        }
        selection = saved
        return true
    }

    /// A page's search text: remembered per sidebar page when `key` is set, else the page's own.
    func search(_ key: SidebarItem?, else local: Binding<String>) -> Binding<String> {
        guard let key else { return local }
        return Binding(get: { self.searches[key] ?? "" }, set: { self.searches[key] = $0 })
    }

    /// Starts from the defaults set in Settings ▸ New Elements (or the built-in ones).
    func newElement(on pageID: UUID, customFields: [CustomField]) {
        editing = ElementDraft(target: .page(pageID), element: NewElementDefaults.current(customFields: customFields))
    }

    func edit(_ element: PageElement, on pageID: UUID) {
        editing = ElementDraft(target: .page(pageID), element: element)
    }

    /// Creates a folder or page below the selected page (at its level), or at the end of the
    /// top level, then selects it and asks for a name.
    func create(folder: Bool, in store: PageStore) {
        let id: UUID
        if case .page(let selected) = selection, store.node(selected) != nil {
            id = store.create(folder: folder, below: selected)
        } else {
            id = store.create(folder: folder, in: nil)
        }
        if !folder { selection = .page(id) }
        renaming = id
    }
}

extension View {
    /// Restores this scroll view's offset when its sidebar page comes back, and records it as it
    /// scrolls. Without a key (pushed pages, See All) it does nothing.
    func remembersScroll(_ key: SidebarItem?) -> some View { modifier(RememberedScroll(key: key)) }
}

private struct RememberedScroll: ViewModifier {
    let key: SidebarItem?
    @Environment(AppNavigator.self) private var navigator
    @State private var position = ScrollPosition()
    /// Offsets reported before the restore are the fresh page's zero; recording them would erase it.
    @State private var restored = false

    func body(content: Content) -> some View {
        if let key {
            content
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, y in
                    if restored { navigator.scrollOffsets[key] = y }
                }
                .onChange(of: navigator.scrollToTop) { _, request in
                    guard request?.item == key else { return }
                    withAnimation(.snappy) { position.scrollTo(edge: .top) }
                }
                .task {
                    if let y = navigator.scrollOffsets[key], y > 0 {
                        // One layout pass first, so the content has a height to scroll within.
                        await Task.yield()
                        position.scrollTo(y: y)
                    }
                    restored = true
                }
        } else {
            content
        }
    }
}

/// Whether a scroll view is moving. Its own object, so starting and stopping a scroll re-renders only the
/// views that read it, not the page.
@MainActor @Observable final class ScrollActivity { var isScrolling = false }

extension View {
    /// On a scroll view: reports whether it's moving.
    func tracksScrolling(_ activity: ScrollActivity) -> some View {
        onScrollPhaseChange { _, phase in
            if activity.isScrolling != phase.isScrolling { activity.isScrolling = phase.isScrolling }
        }
    }

    /// On a scroll view's content: no hover or clicks while it moves. Every tile has hover and tap
    /// handlers, and SwiftUI checking all of them on each scrolled frame was most of the main thread's
    /// work on big grids and artist pages. Only for content without scroll views of its own: switching off
    /// a page holding sideways shelves switched the shelves off too, and they stopped after a pixel. Such
    /// pages hand the activity down instead (`\.scrollActivity`), and each item pauses itself.
    func pausesPointerWhileScrolling(_ activity: ScrollActivity) -> some View {
        modifier(PointerPause(activity: activity))
    }
}

extension EnvironmentValues {
    /// The enclosing page's scroll activity, for items that pause their own pointer handling (see
    /// `pausesPointerWhileScrolling`).
    @Entry var scrollActivity: ScrollActivity? = nil
}

private struct PointerPause: ViewModifier {
    let activity: ScrollActivity
    func body(content: Content) -> some View { content.allowsHitTesting(!activity.isScrolling) }
}

/// Edit / Duplicate / Move / Delete actions for an element, shared by its header and Edit Page mode.
struct ElementMenu: View {
    let element: PageElement
    let pageID: UUID
    let delete: () -> Void
    @Environment(PageStore.self) private var pages
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        let elements = pages.node(pageID)?.page?.elements ?? []
        let index = elements.firstIndex { $0.id == element.id } ?? 0
        Button("Edit Element…", systemImage: "slider.horizontal.3") { navigator.edit(element, on: pageID) }
        Button("Rename…", systemImage: "pencil") { navigator.renamingElement = ElementRef(pageID: pageID, elementID: element.id) }
        Button("Duplicate", systemImage: "plus.square.on.square") { pages.duplicateElement(element.id, on: pageID) }
        Divider()
        Button("Move Up", systemImage: "arrow.up") { pages.moveElement(element.id, on: pageID, by: -1) }
            .disabled(index == 0)
        Button("Move Down", systemImage: "arrow.down") { pages.moveElement(element.id, on: pageID, by: 1) }
            .disabled(index >= elements.count - 1)
        let others = pages.tree.pages.filter { $0.id != pageID }
        if !others.isEmpty {
            Menu("Move to Page", systemImage: "arrow.right.doc.on.clipboard") {
                ForEach(others, id: \.id) { page in
                    Button(page.path) { pages.moveElement(element.id, from: pageID, to: page.id) }
                }
            }
        }
        Divider()
        Button("Delete Element…", systemImage: "trash", role: .destructive, action: delete)
    }
}
