import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Beat ▸ Settings… (⌘,), in the standard tabbed preferences window.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Elements", systemImage: "rectangle.grid.1x2") { ElementSettings() }
            Tab("Playback", systemImage: "waveform") { PlaybackSettings() }
            Tab("Lyrics", systemImage: "quote.bubble") { LyricsSettings() }
            Tab("Artist Info", systemImage: "info.circle") { ArtistInfoSettingsPane() }
        }
    }
}

/// Every pane is a grouped form of the same width, sized to its content.
private struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Form { content() }
            .formStyle(.grouped)
            .frame(width: 480)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Caption: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: General

private struct GeneralSettings: View {
    @AppStorage("appearance.coverColours") private var coverColours = true
    @AppStorage(SidebarTint.key) private var sidebarTint = SidebarTint.full.rawValue
    @AppStorage(LibraryPage.hiddenKey) private var hiddenLibraryPages = ""
    @Environment(PageStore.self) private var pages

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
                HStack {
                    Button("Export…", action: exportSettings)
                    Button("Import…", action: importSettings)
                }
                Caption("Your folders, pages, elements and custom fields, and these preferences, in one file. Only the definitions: tracks are always found in your Music library. Importing replaces what's here. Your Discogs token and play history stay on this Mac.")
            }
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Beat Settings.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try pages.archive().encoded().write(to: url, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let archive: SettingsArchive
        do {
            archive = try SettingsArchive.decode(Data(contentsOf: url))
        } catch {
            NSAlert(error: error).runModal()
            return
        }
        let confirm = NSAlert()
        confirm.messageText = "Replace your pages and preferences?"
        confirm.informativeText = "Your folders, pages, elements and custom fields, and Beat's preferences, will be replaced by the ones in “\(url.lastPathComponent)”. Your Music library and play history aren't affected."
        confirm.addButton(withTitle: "Replace")
        confirm.addButton(withTitle: "Cancel")
        confirm.buttons.first?.hasDestructiveAction = true
        guard confirm.runModal() == .alertFirstButtonReturn else { return }
        archive.applyPreferences(to: .standard)
        pages.replace(with: archive)
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

private struct ElementSettings: View {
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
                Caption("The rules and appearance a new element starts with when you click + on a page.")
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

private struct PlaybackSettings: View {
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

private struct LyricsSettings: View {
    @AppStorage("lyrics.online") private var onlineLyrics = false
    @Environment(\.lyricsProvider) private var lyrics
    @State private var cleared = false

    var body: some View {
        SettingsPane {
            Section("Lyrics") {
                Toggle("Find synced lyrics online (LRCLIB)", isOn: $onlineLyrics)
                Caption("When on, Beat sends each playing song's artist, title, album and length to lrclib.net to look up time-synced lyrics, and saves the answers on this Mac. Lyrics in your files are always used first.")
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

private struct ArtistInfoSettingsPane: View {
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
                Caption("When on, Beat sends artist names to Discogs, with your token, to show photos, bios, members and links on artist pages, and saves the answers on this Mac. With it off, Beat makes no requests to Discogs. Data provided by Discogs.")
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
