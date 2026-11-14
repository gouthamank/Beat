import SwiftUI

/// Library ▸ Health (Mac): `LibraryHealthReport` as one section per check, each listing its first few items with a
/// Show All. Clicking an item opens its album, a song's with the song highlighted, to fix it in Music.
struct LibraryHealthView: View {
    /// A finished report, for snapshot tests; otherwise worked out from the library.
    var report: LibraryHealthReport?
    @Environment(LibraryStore.self) private var library
    @Environment(\.pageInset) private var pageInset
    @State private var computed: LibraryHealthReport?
    /// Sections showing every item rather than the first few.
    @State private var expanded: Set<LibraryHealthReport.Check> = []

    /// Enough to see what a section is about; long ones (no album artist can run to thousands) wait for Show All.
    private static let preview = 8

    private var shown: LibraryHealthReport? { report ?? computed }

    var body: some View {
        Group {
            if let shown {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(shown.sections) { section($0) }
                    }
                    .padding(pageInset)
                    .frame(maxWidth: 980, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
                .remembersScroll(.health)
            } else {
                ProgressView("Checking your library…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Health")
        .pageSubtitle(subtitle)
        .task(id: library.version) {
            guard report == nil else { return }
            computed = await LibraryHealthCache.report(for: library.snapshot, version: library.version)
        }
    }

    private var subtitle: String {
        guard let shown else { return "" }
        let count = shown.problemCount
        return count == 0 ? "Nothing to fix" : count.counted("thing to look at", "things to look at")
    }

    private func section(_ section: LibraryHealthReport.Section) -> some View {
        let all = expanded.contains(section.check)
        let items = all ? section.items : Array(section.items.prefix(Self.preview))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // One width for every symbol, so the titles line up.
                Image(systemName: section.check.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Text(section.check.title)
                    .font(.title3.weight(.semibold))
                Text(section.items.isEmpty ? "" : section.items.count.formatted())
                    .foregroundStyle(.secondary)
            }
            Text(section.check.explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if section.items.isEmpty {
                Label("Nothing to fix", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else {
                // Lazy: Show All on "no album artist" can mean thousands of rows.
                LazyVStack(spacing: 0) {
                    ForEach(items) { HealthRow(item: $0) }
                    if section.items.count > Self.preview {
                        Button(all ? "Show Fewer" : "Show All \(section.items.count.formatted())") {
                            if all { expanded.remove(section.check) } else { expanded.insert(section.check) }
                        }
                        .buttonStyle(.borderless)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                    }
                }
                .padding(8)
                .beatGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .accessibilityIdentifier("health.\(section.check.rawValue)")
    }
}

/// One album or song: cover, name, where it is, and what's wrong. Opens its album, the cover flying out of the row's
/// thumbnail and back into it on the way back, as from an album tile (without a tile to land in, it hung over the
/// page before fading).
private struct HealthRow: View {
    let item: LibraryHealthReport.Item
    @Environment(AppNavigator.self) private var navigator
    @Environment(HeroTransition.self) private var hero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @State private var probe = FrameProbe()
    /// Clicked: keeps the probe until the zoom has measured it.
    @State private var armed = false

    private static let coverRadius: CGFloat = 4
    private var subject: HeroSubject { .album(item.target.albumID) }
    /// Only a row that might start or receive a zoom carries the AppKit probe, as with album tiles.
    private var needsProbe: Bool { hovering || armed || hero.lastOpened == subject }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                ArtworkView(albumID: item.target.albumID, cornerRadius: Self.coverRadius)
                    .frame(width: 36, height: 36)
                    .background { if needsProbe { Color.clear.frameProbe(probe) } }
                    .opacity(hero.isReturning(to: subject) ? 0 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title).lineLimit(1)
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                Text(item.problem)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.primary.opacity(hovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            hovering = h
            // Pointer on the row: the album's colours are usually ready before the click, as with tiles.
            if h { navigator.coverTint.prefetch(.album(item.target.albumID)) }
        }
        .task(id: item.id) { hero.registerTile(probe, for: subject, cornerRadius: Self.coverRadius) }
    }

    private func open() {
        armed = true
        let track: PersistentID? = if case .song(let id, _) = item.target { id } else { nil }
        navigator.openWhenReady(.album(item.target.albumID)) {
            hero.open(subject, from: probe, cornerRadius: Self.coverRadius, navigator: navigator,
                      reduceMotion: reduceMotion, highlighting: track)
        }
    }
}

/// The last report, so coming back to Health is instant; worked out again only when the library changes. A file
/// moved away without Music noticing shows up at the next library change.
@MainActor
enum LibraryHealthCache {
    private static var last: (version: Int, report: LibraryHealthReport)?

    static func report(for snapshot: LibrarySnapshot, version: Int) async -> LibraryHealthReport {
        if let last, last.version == version { return last.report }
        let report = await Task.detached(priority: .utility) {
            LibraryHealth.check(snapshot) { FileManager.default.fileExists(atPath: $0.path) }
        }.value
        last = (version, report)
        return report
    }
}
