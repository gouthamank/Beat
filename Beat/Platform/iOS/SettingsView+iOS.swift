import SwiftUI
import UniformTypeIdentifiers

/// Settings on iPad and iPhone, presented as a sheet from the sidebar: the usual Settings list, each section opening
/// its form (six tabs overflowed a phone's tab bar into "More").
struct SettingsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { GeneralSettings().navigationTitle("General") } label: { Label("General", systemImage: "gearshape") }
                NavigationLink { ElementSettings().navigationTitle("Elements") } label: { Label("Elements", systemImage: "rectangle.grid.1x2") }
                NavigationLink { PlaybackSettings().navigationTitle("Playback") } label: { Label("Playback", systemImage: "waveform") }
                NavigationLink { LyricsSettings().navigationTitle("Lyrics") } label: { Label("Lyrics", systemImage: "quote.bubble") }
                NavigationLink { ArtistInfoSettingsPane().navigationTitle("Artist Info") } label: { Label("Artist Info", systemImage: "info.circle") }
                // Only in builds with a Last.fm key (Config/Secrets.xcconfig); see README.
                if LastFMCredentials.bundled != nil {
                    NavigationLink { LastFMSettingsPane().navigationTitle("Last.fm") } label: { Label("Last.fm", systemImage: "dot.radiowaves.up.forward") }
                }
            }
            // Where the Mac has its About panel.
            Section {
                LabeledContent("Version", value: AppVersion.display)
            }
        }
        .navigationTitle("Settings")
    }
}

/// Export and Import for the settings file, through the Files picker and a confirmation, where the Mac uses save
/// and open panels.
struct SettingsFileButtons: View {
    @Environment(PageStore.self) private var pages
    @State private var exporting = false
    @State private var importing = false
    /// A file read and waiting for the user to confirm it replaces everything.
    @State private var pendingImport: (archive: SettingsArchive, name: String)?
    @State private var failure: String?

    var body: some View {
        HStack(spacing: 20) {
            // Each sheet on its own button: SwiftUI can drop one of two file sheets attached to the same view.
            Button("Export…") { exporting = true }
                .fileExporter(isPresented: $exporting, document: SettingsFile(data: (try? pages.archive().encoded()) ?? Data()),
                              contentType: .json, defaultFilename: "Beat Settings") { result in
                    if case .failure(let error) = result { failure = error.localizedDescription }
                }
            Button("Import…") { importing = true }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                    do {
                        let url = try result.get()
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        pendingImport = (try SettingsArchive.decode(Data(contentsOf: url)), url.lastPathComponent)
                    } catch {
                        failure = error.localizedDescription
                    }
                }
        }
        // Each its own tap target: in a form row, plain buttons share the row's, so a tap fired both and Export's
        // save sheet opened in place of Import's.
        .buttonStyle(.borderless)
        .alert("Replace your pages and preferences?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("Replace", role: .destructive) {
                guard let pending = pendingImport else { return }
                pending.archive.applyPreferences(to: .standard)
                pages.replace(with: pending.archive)
                pendingImport = nil
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Your folders, pages, elements and custom fields, and Beat's preferences, will be replaced by the ones in “\(pendingImport?.name ?? "")”. Your music library and play history aren't affected.")
        }
        .alert("Couldn't Use the Settings File", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }
}

/// The settings file for `fileExporter`: the archive's JSON, written as is.
private struct SettingsFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) { data = configuration.file.regularFileContents ?? Data() }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
