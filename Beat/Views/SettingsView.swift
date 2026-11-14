import SwiftUI

// The panes of Beat's settings, shared. Each platform puts them in its own container (`SettingsView`): the Mac's
// tabbed Settings window, two columns on iPad and a list on iPhone (Platform/*/SettingsView+*.swift), and brings its own
// Export/Import buttons (`SettingsFileButtons`).

/// Every pane is a grouped form of the same width, sized to its content.
private struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form { content() }
            .formStyle(.grouped)
        #if os(macOS)
            // The Mac's Settings window sizes to its pane; on iPad and iPhone the form fills the screen and scrolls.
            .frame(width: 480)
            .fixedSize(horizontal: false, vertical: true)
        #endif
    }
}

struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: General

struct GeneralSettings: View {
    @AppStorage("appearance.coverColours") private var coverColours = true
    @AppStorage(SidebarTint.key) private var sidebarTint = SidebarTint.full.rawValue
    @AppStorage(LibraryPage.hiddenKey) private var hiddenLibraryPages = ""

    var body: some View {
        SettingsPane {
            Section("Appearance") {
                Picker("Album pages and Now Playing", selection: $coverColours) {
                    Text("Cover Colours").tag(true)
                    Text("Plain").tag(false)
                }
                .pickerStyle(.segmented)
                Caption(coverColours
                        ? "Backgrounds and text take their colours from the album cover."
                        : "The standard look, with a soft blur of the cover behind it.")
                Picker("Sidebar on album and artist pages", selection: $sidebarTint) {
                    ForEach(SidebarTint.allCases, id: \.self) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .disabled(!coverColours)
            }

            Section("Library") {
                ForEach(LibraryPage.allCases) { page in
                    Toggle(isOn: shown(page)) {
                        Label(page.title, systemImage: page.symbol)
                    }
                }
                Caption("Choose which Library pages appear in the sidebar. Hiding one doesn't change your own pages or your Music library.")
            }

            Section("Settings File") {
                SettingsFileButtons()
                Caption("Your folders, pages, elements and custom fields, and these preferences, in one file. Only the definitions: tracks are always found in your Music library. Importing replaces what's here. Your Discogs token and play history stay on \(thisDevice).")
            }
        }
    }

    private func shown(_ page: LibraryPage) -> Binding<Bool> {
        Binding(
            get: { !LibraryPage.hidden(in: hiddenLibraryPages).contains(page) },
            set: { show in
                var hidden = LibraryPage.hidden(in: hiddenLibraryPages)
                if show { hidden.remove(page) } else { hidden.insert(page) }
                hiddenLibraryPages = LibraryPage.stored(hidden)
            }
        )
    }
}

// MARK: Elements

struct ElementSettings: View {
    @AppStorage(NewElementDefaults.key) private var savedElementDefaults: Data?
    @Environment(PageStore.self) private var pages
    @State private var editingDefaults: ElementDraft?

    var body: some View {
        SettingsPane {
            Section("New Elements") {
                LabeledContent("Start with", value: NewElementDefaults.summary(elementDefaults))
                HStack {
                    Button("Edit Defaults…") {
                        editingDefaults = ElementDraft(target: .defaults, element: elementDefaults)
                    }
                    Button("Reset to Built-in") { savedElementDefaults = nil }
                        .disabled(savedElementDefaults == nil)
                }
                Caption("The rules and appearance a new element starts with when you add one with + on a page.")
            }
        }
        .sheet(item: $editingDefaults) { FilterEditorSheet(draft: $0) }
    }

    /// Reads the saved data so the summary updates as soon as the editor saves or Reset clears it.
    private var elementDefaults: PageElement {
        _ = savedElementDefaults
        return NewElementDefaults.saved()?.refreshingCustomFields(pages.customFields) ?? NewElementDefaults.builtIn
    }
}

// MARK: Playback

struct PlaybackSettings: View {
    @AppStorage("visualizer.enabled") private var visualizerEnabled = true

    var body: some View {
        SettingsPane {
            Section("Visualizer") {
                Toggle("Enable visualizer", isOn: $visualizerEnabled)
                Caption("Lets Beat read the audio it's playing to draw the visualizer. The sound itself isn't changed. Turn it off if you ever hear a glitch; it takes effect from the next song.")
            }
        }
    }
}

// MARK: Lyrics

struct LyricsSettings: View {
    @AppStorage("lyrics.online") private var onlineLyrics = false
    @Environment(\.lyricsProvider) private var lyrics
    @State private var cleared = false

    var body: some View {
        SettingsPane {
            Section("Lyrics") {
                Toggle("Find synced lyrics online (LRCLIB)", isOn: $onlineLyrics)
                Caption("When on, Beat sends each playing song's artist, title, album and length to lrclib.net to look up time-synced lyrics, and saves the answers on \(thisDevice). Lyrics in your files are always used first.")
                Button(cleared ? "Downloaded Lyrics Cleared" : "Clear Downloaded Lyrics") {
                    Task {
                        await lyrics?.clearDownloaded()
                        cleared = true
                    }
                }
                .disabled(cleared)
            }
        }
    }
}

// MARK: Artist info

struct ArtistInfoSettingsPane: View {
    @AppStorage(ArtistInfoSettings.onlineKey) private var artistInfoOnline = false
    @Environment(\.artistInfoProvider) private var artistInfo
    @Environment(ArtistImages.self) private var artistImages: ArtistImages?
    @State private var discogsToken = ""
    @State private var cleared = false

    var body: some View {
        SettingsPane {
            Section("Discogs") {
                Toggle("Look up artist info on Discogs", isOn: $artistInfoOnline)
                SecureField("Discogs token", text: $discogsToken, prompt: Text("Personal access token"))
                    .onChange(of: discogsToken) { _, token in Keychain.set(token, for: ArtistInfoSettings.tokenAccount) }
                Link("Get a personal access token from Discogs…", destination: URL(string: "https://www.discogs.com/settings/developers")!)
                    .font(.callout)
                Caption("When on, Beat sends artist names to Discogs, with your token, to show photos, bios, members and links on artist pages, and saves the answers on \(thisDevice). With it off, Beat makes no requests to Discogs. Data provided by Discogs.")
                Button(cleared ? "Downloaded Artist Info Cleared" : "Clear Downloaded Artist Info") {
                    Task {
                        await artistInfo?.clearDownloaded()
                        artistImages?.clear()
                        cleared = true
                    }
                }
                .disabled(cleared)
            }
        }
        .onAppear { discogsToken = Keychain.string(for: ArtistInfoSettings.tokenAccount) ?? "" }
    }
}

// MARK: Last.fm

struct LastFMSettingsPane: View {
    @AppStorage(LastFMSettings.enabledKey) private var enabled = false
    @Environment(Scrobbler.self) private var scrobbler

    var body: some View {
        SettingsPane {
            Section("Last.fm") {
                Toggle("Scrobble to Last.fm", isOn: $enabled)
                LabeledContent("Account") { account }
                if let status { Text(status).font(.callout).foregroundStyle(.secondary) }
                Caption("When on, Beat sends each song you play past halfway (or past 4 minutes) to Last.fm: its artist, title, album, track number, length and when you played it, and shows the song playing now on your profile. Plays made offline are sent later. With it off, Beat makes no requests to Last.fm.")
            }
        }
        .onChange(of: enabled) { _, on in if on { scrobbler.flush() } }
    }

    @ViewBuilder private var account: some View {
        switch scrobbler.connection {
        case .disconnected:
            Button("Connect…") { scrobbler.connect() }
        case .waitingForApproval:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for approval in your browser…").foregroundStyle(.secondary)
                Button("Cancel") { scrobbler.cancelConnect() }
            }
        case .connected(let username):
            HStack(spacing: 8) {
                Text(username)
                Button("Disconnect") { scrobbler.disconnect() }
            }
        }
    }

    private var status: String? {
        let waiting = scrobbler.pendingCount == 1 ? "1 scrobble is waiting to send." : "\(scrobbler.pendingCount) scrobbles are waiting to send."
        switch scrobbler.status {
        case .idle, .sending: return scrobbler.pendingCount > 0 ? waiting : nil
        case .retrying(let message): return "\(message) \(waiting) Beat will try again shortly."
        case .needsReconnect: return "Last.fm signed Beat out. Connect again to keep scrobbling; your plays are saved meanwhile."
        case .failed(let message): return message
        }
    }
}
