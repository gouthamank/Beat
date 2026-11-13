import SwiftUI

@main
struct BeatApp: App {
    @State private var library: LibraryStore
    @State private var artwork: ArtworkCache
    @State private var history: PlayHistoryStore
    @State private var queue: PlaybackQueue
    @State private var pages = PageStore()
    @State private var navigator: AppNavigator
    @State private var hero: HeroTransition
    @State private var lyrics = LyricsProvider()
    @State private var artistInfo = ArtistInfoProvider()
    @State private var artistImages = ArtistImages()
    @State private var scrobbler: Scrobbler

    init() {
        configurePlatform()
        let library = LibraryStore()
        let artwork = ArtworkCache(loader: library.loader)
        // Saved thumbnails are named for the art Music has now; changed art is forgotten and loaded again.
        artwork.currentLabel = { [unowned library] in library.snapshot.artworkLabel(for: $0) }
        library.onRead = { [unowned artwork] in artwork.pruneSavedThumbnails(keeping: $0) }
        library.onAccessLost = { [unowned artwork] in artwork.removeSavedThumbnails() }
        let history = PlayHistoryStore()
        let scrobbler = Scrobbler()
        _scrobbler = State(initialValue: scrobbler)
        _library = State(initialValue: library)
        _artwork = State(initialValue: artwork)
        _history = State(initialValue: history)
        _queue = State(initialValue: PlaybackQueue(history: history, artwork: artwork, scrobbler: scrobbler))
        let navigator = AppNavigator()
        let hero = HeroTransition()
        navigator.hero = hero
        navigator.coverTint.configure(library: library, history: history, artwork: artwork)
        library.onArtworkChanged = { [unowned artwork, unowned navigator] changed in
            guard !changed.isEmpty else { return }
            artwork.invalidate(changed)
            // The page, sidebar and bar may be coloured from a cover that just changed.
            navigator.coverTint.refresh()
        }
        _navigator = State(initialValue: navigator)
        _hero = State(initialValue: hero)
    }

    var body: some Scene {
        WindowGroup("Beat") {
            withStores(RootView().platformWindow(queue: queue, navigator: navigator))
        }
        .platformWindowStyle()
        .commands {
            PlatformCommands()
            CommandGroup(after: .sidebar) {
                Button("Back") { navigator.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!navigator.canGoBack)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Page") { navigator.create(folder: false, in: pages) }
                    .keyboardShortcut("n")
                Button("New Folder") { navigator.create(folder: true, in: pages) }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            PlaybackCommands(queue: queue, navigator: navigator)
        }

        #if os(macOS)
        settingsWindow
        #endif
    }

    /// Every store the app's views read, for the main window and the Mac's Settings window alike.
    func withStores<Content: View>(_ content: Content) -> some View {
        content
            .environment(library)
            .environment(artwork)
            .environment(history)
            .environment(queue)
            .environment(pages)
            .environment(navigator)
            .environment(hero)
            .environment(\.lyricsProvider, lyrics)
            .environment(\.artistInfoProvider, artistInfo)
            .environment(artistImages)
            .environment(scrobbler)
    }
}
