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

    init() {
        let library = LibraryStore()
        let artwork = ArtworkCache(loader: library.loader)
        let history = PlayHistoryStore()
        _library = State(initialValue: library)
        _artwork = State(initialValue: artwork)
        _history = State(initialValue: history)
        _queue = State(initialValue: PlaybackQueue(history: history, artwork: artwork))
        let navigator = AppNavigator()
        let hero = HeroTransition()
        navigator.hero = hero
        navigator.coverTint.configure(library: library, history: history, artwork: artwork)
        _navigator = State(initialValue: navigator)
        _hero = State(initialValue: hero)
    }

    var body: some Scene {
        WindowGroup("Beat") {
            RootView()
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
                // Minimum width is set on RootView's detail column (see there).
                .frame(minHeight: 560)
                .onAppear {
                    SpaceBarMonitor.install(queue: queue)
                    SidebarReclickMonitor.install(navigator: navigator)
                    SwipeBackMonitor.install(navigator: navigator)
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Beat") { AboutPanel.show() }
            }
            SidebarCommands()
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

        Settings {
            // Everything the main window has: Settings hosts the element editor (for new-element defaults),
            // whose preview renders real elements.
            SettingsView()
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
        }
    }
}

/// The standard About panel, with the build's commit beside its build number: "Version 1.0 (42 · a1b2c3d)".
@MainActor
enum AboutPanel {
    static func show() {
        let info = Bundle.main.infoDictionary ?? [:]
        let build = info["CFBundleVersion"] as? String ?? ""
        let commit = info["BeatCommit"] as? String ?? ""
        NSApp.orderFrontStandardAboutPanel(options: [.applicationVersion: commit.isEmpty ? build : "\(build) · \(commit)"])
        NSApp.activate()
    }
}
