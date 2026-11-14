import SwiftUI

/// Library ▸ Songs on iPad and iPhone, for now: a SwiftUI list with the Mac table's inputs, an album artist per
/// section and each album as its cover beside its songs. A UIKit collection view (pinned artist headers, covers
/// placed beside the songs as on the Mac) replaces it in the Songs milestone of the iOS port.
struct AlbumSongsTable: View {
    /// As on the Mac, where table cells live outside SwiftUI's environment.
    struct Stores {
        let library: LibraryStore
        let queue: PlaybackQueue
        let navigator: AppNavigator
        let hero: HeroTransition
        let artwork: ArtworkCache
    }

    let sections: [ArtistSection]
    /// The Mac table's rows; the list here lays itself out, so it's always nil.
    let layout: AlbumSongsLayout?
    let generation: Int
    let playOrder: [Track]
    let extras: [ExtraColumn]
    /// The Mac's column order and widths; the list here has no columns to move or resize.
    let columnSettings: SongColumnSettings
    let customValues: [UUID: [PersistentID: String]]
    @Binding var artWidth: Double
    let currentID: PersistentID?
    let isPlaying: Bool
    let playbackAccent: PlatformColor
    let bottomInset: CGFloat
    let scrollToTopToken: Int
    /// A song to scroll to and highlight for a moment (Quick Open's Show in Songs), once it's in the list.
    let highlight: TrackHighlight?
    let stores: Stores

    static let artRange: ClosedRange<Double> = 90...360
    /// No layout to build in the background (see `layout`).
    static var layoutMetrics: AlbumSongsLayout.Metrics? { nil }
    @Environment(\.compactLayout) private var compact
    @State private var flashed: PersistentID?

    var body: some View {
        // Play order index per song, so a tap plays from that song on through the whole list.
        let position = Dictionary(playOrder.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
        ScrollViewReader { proxy in
            List {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.groups) { group in
                            let songs = VStack(spacing: 0) {
                                ForEach(group.tracks) { track in
                                    row(track) { stores.queue.play(playOrder, startAt: position[track.id] ?? 0) }
                                }
                            }
                            if compact {
                                // A phone has no room for a cover column: the album is a small header over its songs.
                                VStack(alignment: .leading, spacing: 8) {
                                    albumHeader(group.album)
                                    songs
                                }
                                .padding(.vertical, 6)
                            } else {
                                HStack(alignment: .top, spacing: 16) {
                                    CoverBlock(album: group.album, stores: stores)
                                        .frame(width: artWidth)
                                    songs
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    } header: {
                        artistHeader(section.name)
                    }
                }
            }
            .listStyle(.plain)
            .contentMargins(.bottom, bottomInset, for: .scrollContent)
            // Not keyed on `generation`: the model bumps it whenever the page reappears, and a list rebuilt from it jumped
            // back to the top after every album opened from it. Rows update by their own ids.
            // Back to the top only when asked (`scrollToTopToken`), as the Mac's table does.
            .onChange(of: scrollToTopToken) {
                guard let first = sections.first else { return }
                withAnimation(.snappy) { proxy.scrollTo(first.id, anchor: .top) }
            }
            // Again with each new set of rows: a cleared search brings the song back a moment later.
            .task(id: [highlight?.token ?? -1, generation]) {
                guard let request = highlight,
                      let group = sections.lazy.flatMap(\.groups).first(where: { $0.tracks.contains { $0.id == request.trackID } })
                else { return }
                // A list row is the whole album, so that's what scrolls into view; the song itself is highlighted.
                withAnimation(.snappy) { proxy.scrollTo(group.id, anchor: .center) }
                flashed = request.trackID
                stores.navigator.songsHighlight = nil
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation(.easeOut(duration: 0.6)) { if flashed == request.trackID { flashed = nil } }
                }
            }
        }
    }

    /// The album artist, pinned while their albums scroll by. Plain lists draw pinned headers see-through, which
    /// let the songs show through the name, so the header brings its own bar.
    private func artistHeader(_ name: String) -> some View {
        Text(name)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.bar)
            .listRowInsets(EdgeInsets())
    }

    /// The album over its songs on a phone: a small cover, the title and year; tapping it opens the album.
    private func albumHeader(_ album: Album) -> some View {
        // Through `openWhenReady`, as every other tile: opened before its colours were known, the page kept the
        // status bar it started with (white on a pale cover).
        Button { stores.navigator.openWhenReady(.album(album.id)) { stores.navigator.openAlbum(album.id) } } label: {
            HStack(spacing: 12) {
                ArtworkView(albumID: album.id, cornerRadius: 6)
                    .frame(width: 56, height: 56)
                    .zoomSource(.album(album.id))
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title).font(.headline).lineLimit(2)
                    if album.year > 0 {
                        Text(String(album.year)).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // For the phone's UI test that checks Songs keeps its place after an album.
        .accessibilityIdentifier("songs.album.\(album.title)")
    }

    private func row(_ track: Track, play: @escaping () -> Void) -> some View {
        Button(action: play) {
            HStack(spacing: 10) {
                Text(track.trackNumber > 0 ? "\(track.trackNumber)" : "")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 26, alignment: .trailing)
                Text(track.title)
                    .fontWeight(track.id == currentID ? .semibold : .regular)
                    .foregroundStyle(track.id == currentID ? Color(playbackAccent) : .primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(track.duration.trackTime)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 7)
            // The system accent, as on album pages: a highlight, not playback (`playbackAccent`).
            .background(flashed == track.id ? Color.accentColor.opacity(0.3) : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
