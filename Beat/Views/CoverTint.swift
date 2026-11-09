import SwiftUI

/// The one source of cover colours. The front album or artist page's background and text, the sidebar,
/// the window's light/dark and the now-playing bar all read `current`, so they always match.
///
/// Colours follow the navigation path, not any view's lifecycle: every route change (sidebar switches
/// included) asks for the front page's colours and applies the answer only if nothing has changed since.
/// Colours already known apply in the same update as the navigation, so a page opens in its colours rather
/// than flipping into them a moment later; unknown ones are worked out and applied if still wanted. A late
/// answer for a page you've left can never land, whatever order views appear and disappear in.
@MainActor
@Observable
final class CoverTint {
    struct Current: Equatable {
        /// The page these colours belong to; pages only use colours that are theirs.
        let route: Route
        let albumID: PersistentID
        let palette: ArtworkPalette
    }

    private(set) var current: Current?

    /// An optional pause before working out colours that aren't known yet. Zero by default: waiting showed
    /// pages uncoloured first, a visible two-step flicker, and the latest-wins check alone prevents races.
    @ObservationIgnored var settle: Duration = .zero
    /// The album whose cover colours a page: an album page's own, an artist's featured album.
    @ObservationIgnored var albumForRoute: (Route) -> PersistentID? = { _ in nil }
    @ObservationIgnored var cachedPalette: (PersistentID) -> ArtworkPalette? = { _ in nil }
    @ObservationIgnored var loadPalette: (PersistentID) async -> ArtworkPalette? = { _ in nil }
    /// Settings ▸ General ▸ Cover Colours; Plain means no colours anywhere.
    @ObservationIgnored var isEnabled: () -> Bool = { UserDefaults.standard.object(forKey: "appearance.coverColours") as? Bool ?? true }

    @ObservationIgnored private var route: Route?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Wires the lookups to the app's stores.
    func configure(library: LibraryStore, history: PlayHistoryStore, artwork: ArtworkCache) {
        albumForRoute = { route in
            switch route {
            case .album(let id):
                return id
            case .artist(let id):
                let snapshot = library.snapshot
                guard let artist = snapshot.artistsByID[id] else { return nil }
                return ArtistPageContent.featuredAlbumID(artist: artist, snapshot: snapshot, history: history.stats)
            case .genre, .element:
                return nil
            }
        }
        cachedPalette = { artwork.cachedPalette(album: $0) }
        loadPalette = { await artwork.palette(album: $0) }
    }

    /// The front page changed (or there's none: nil).
    func show(_ route: Route?) {
        self.route = route
        resolve()
    }

    /// Works out a page's colours ahead of opening it, so it opens already coloured. Returns once they're
    /// known, or after `limit` at most, so a slow cover never holds up navigation for long.
    func prepare(_ route: Route, within limit: Duration = .milliseconds(250)) async {
        guard isEnabled(), let albumID = albumForRoute(route), cachedPalette(albumID) == nil else { return }
        let load = Task { _ = await self.loadPalette(albumID) }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await load.value }
            group.addTask { try? await Task.sleep(for: limit) }
            await group.next()
            group.cancelAll()
        }
    }

    /// Warms a page's colours in the background (a tile under the pointer), with no deadline.
    func prefetch(_ route: Route) {
        Task { await prepare(route, within: .seconds(10)) }
    }

    /// Same page, but its colours may differ: Cover Colours toggled, or plays changed its featured album.
    func refresh() {
        resolve()
    }

    /// Waits for the colours being worked out, for tests.
    func settled() async {
        await task?.value
    }

    private func resolve() {
        generation += 1
        let generation = generation
        task?.cancel()
        task = nil

        // Another page's colours mustn't linger while this page's are worked out.
        if let current, current.route != route { withAnimation(Motion.fade) { self.current = nil } }
        guard let route, isEnabled(), let albumID = albumForRoute(route) else {
            if current != nil { withAnimation(Motion.fade) { current = nil } }
            return
        }

        // Known colours apply now, together with the navigation that asked for them.
        if let cached = cachedPalette(albumID) {
            let next = Current(route: route, albumID: albumID, palette: cached)
            if next != current { withAnimation(Motion.fade) { current = next } }
            return
        }

        task = Task { [weak self] in
            guard let self else { return }
            if self.settle > .zero { try? await Task.sleep(for: self.settle) }
            guard generation == self.generation else { return }
            var palette = self.cachedPalette(albumID)
            if palette == nil { palette = await self.loadPalette(albumID) }
            guard generation == self.generation else { return }
            let next = palette.map { Current(route: route, albumID: albumID, palette: $0) }
            if next != self.current { withAnimation(Motion.fade) { self.current = next } }
        }
    }
}
