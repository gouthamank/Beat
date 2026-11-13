import SwiftUI

// Library ▸ Songs on an AppKit table. A SwiftUI lazy stack of ~3k variable-height album blocks spent
// most of its time in layout and hover hit-testing; NSTableView reuses a screenful of rows instead.

/// Library ▸ Songs flattened into table rows: a floating header per album artist, then each album's
/// songs between a top spacer and a bottom spacer tall enough for the album's cover block.
struct AlbumSongsLayout {
    struct Metrics: Equatable {
        var song: CGFloat
        var songWithArtist: CGFloat
        var artist: CGFloat
        /// Space above and below each album's block.
        var padding: CGFloat = 14
        /// The album title under the square cover.
        var coverTitle: CGFloat
        /// The year line under that.
        var year: CGFloat
    }

    enum Row: Equatable {
        case artist(section: Int)
        case albumTop(album: Int)
        /// `play` is the song's index in the page's play order.
        case song(album: Int, track: Int, play: Int)
        case albumBottom(album: Int)
    }

    struct AlbumSpan: Equatable {
        let section: Int
        let group: Int
        /// The album's top and bottom spacer rows.
        let top: Int
        let bottom: Int
        let songsHeight: CGFloat
        let hasYear: Bool
        let isFirstInSection: Bool
    }

    let metrics: Metrics
    private(set) var rows: [Row] = []
    private(set) var albums: [AlbumSpan] = []
    private(set) var rowOfTrack: [PersistentID: Int] = [:]
    private var songHeights: [CGFloat] = []

    init(sections: [ArtistSection], metrics: Metrics) {
        self.metrics = metrics
        var play = 0
        for (s, section) in sections.enumerated() {
            rows.append(.artist(section: s))
            songHeights.append(0)
            for (g, group) in section.groups.enumerated() {
                let a = albums.count
                let top = rows.count
                rows.append(.albumTop(album: a))
                songHeights.append(0)
                var height: CGFloat = 0
                for (t, track) in group.tracks.enumerated() {
                    let h = track.displayArtist != group.album.artist ? metrics.songWithArtist : metrics.song
                    rowOfTrack[track.id] = rows.count
                    rows.append(.song(album: a, track: t, play: play))
                    songHeights.append(h)
                    height += h
                    play += 1
                }
                rows.append(.albumBottom(album: a))
                songHeights.append(0)
                albums.append(AlbumSpan(section: s, group: g, top: top, bottom: rows.count - 1, songsHeight: height,
                                        hasYear: group.album.year > 0, isFirstInSection: g == 0))
            }
        }
    }

    /// The cover, its title and (when known) its year.
    func coverHeight(album a: Int, artWidth: CGFloat) -> CGFloat {
        artWidth + metrics.coverTitle + (albums[a].hasYear ? metrics.year : 0)
    }

    func height(of row: Int, artWidth: CGFloat) -> CGFloat {
        switch rows[row] {
        case .artist: metrics.artist
        case .albumTop: metrics.padding
        case .song: songHeights[row]
        case .albumBottom(let a):
            max(metrics.padding, coverHeight(album: a, artWidth: artWidth) + metrics.padding - albums[a].songsHeight)
        }
    }

    func isSong(_ row: Int) -> Bool {
        if case .song = rows[row] { true } else { false }
    }

    /// The artist section a row belongs to, for the scrollbar's letter bubble.
    func section(atRow row: Int) -> Int? {
        guard rows.indices.contains(row) else { return nil }
        switch rows[row] {
        case .artist(let section): return section
        case .albumTop(let a), .albumBottom(let a): return albums[a].section
        case .song(let a, _, _): return albums[a].section
        }
    }

    /// Albums whose rows overlap `first...last`, by binary search (albums are in row order).
    func albumRange(overlapping first: Int, _ last: Int) -> Range<Int> {
        var lo = 0, hi = albums.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if albums[mid].bottom < first { lo = mid + 1 } else { hi = mid }
        }
        var end = lo
        while end < albums.count, albums[end].top <= last { end += 1 }
        return lo..<end
    }
}

// MARK: - Views

/// An album's cover, title and year, shown beside its songs. Not a tile: no hover or menu, and a click shows
/// the cover full-window, as on album pages. The rows below already play and open the album.
struct CoverBlock: View {
    let album: Album
    let stores: AlbumSongsTable.Stores
    @State private var probe = FrameProbe()

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Sizes match AlbumTile's, which `AlbumSongsLayout.Metrics` was measured from.
            VStack(alignment: .leading, spacing: 6) {
                // A fixed base for the probe; the cover swaps placeholder for image inside it (see ArtistArtwork).
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay { ArtworkView(albumID: album.id, cornerRadius: 10) }
                    .frameProbe(probe)
                    // Drawn from the outline: SwiftUI's `.shadow` was redrawn for every cover on every scrolled frame.
                    .background(ShapeShadow(shape: RoundedRectangle(cornerRadius: 10, style: .continuous),
                                            opacity: 0.15, radius: 6, y: 3))
                    .coverViewerOnClick(album, from: probe)
                Text(album.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
            if album.year > 0 {
                Text(String(album.year))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(stores.library)
        .environment(stores.queue)
        .environment(stores.navigator)
        .environment(stores.hero)
        .environment(stores.artwork)
    }
}
