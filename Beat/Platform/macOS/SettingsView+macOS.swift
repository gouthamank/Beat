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
            // Only in builds with a Last.fm key (Config/Secrets.xcconfig); see README.
            if LastFMCredentials.bundled != nil {
                Tab("Last.fm", systemImage: "dot.radiowaves.up.forward") { LastFMSettingsPane() }
            }
        }
    }
}

/// Export and Import for the settings file, with the save and open panels and an alert to confirm the import.
struct SettingsFileButtons: View {
    @Environment(PageStore.self) private var pages

    var body: some View {
        HStack {
            Button("Export…", action: exportSettings)
            Button("Import…", action: importSettings)
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
}
