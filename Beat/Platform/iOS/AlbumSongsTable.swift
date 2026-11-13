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
    let generation: Int
    let playOrder: [Track]
    let extras: [ExtraColumn]
    let customValues: [UUID: [PersistentID: String]]
    @Binding var artWidth: Double
    let currentID: PersistentID?
    let isPlaying: Bool
    let playbackAccent: PlatformColor
    let bottomInset: CGFloat
    let scrollToTopToken: Int
    let stores: Stores

    static let artRange: ClosedRange<Double> = 90...360
    @Environment(\.compactLayout) private var compact

    var body: some View {
        // Play order index per song, so a tap plays from that song on through the whole list.
        let position = Dictionary(playOrder.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
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
        .id(generation)
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
        Button { stores.navigator.openAlbum(album.id) } label: {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
