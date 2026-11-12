import AppKit
import ImageIO
import Observation

@MainActor
@Observable
final class ArtworkCache {
    enum Size: Int {
        case thumbnail = 400
        case large = 1200
        /// For the full-window art viewer only.
        case full = 4096
    }

    @ObservationIgnored private let loader: LibraryLoader
    @ObservationIgnored private let disk: ArtworkDiskCache
    /// What each source's art is now (`LibrarySnapshot.artworkLabel`), for naming saved thumbnails. Set by the app.
    @ObservationIgnored var currentLabel: @MainActor (ArtworkSource) -> ArtworkLabel? = { _ in nil }
    /// Bumped for a source when its art changes in Music, so views showing it load it again.
    private var revisions: [ArtworkSource: Int] = [:]
    @ObservationIgnored private let cache = NSCache<NSString, NSImage>()
    @ObservationIgnored private var inFlight: [NSString: Task<NSImage?, Never>] = [:]
    /// Small and few (one per album visited or track played), so a plain dictionary rather than NSCache.
    @ObservationIgnored private var palettes: [ArtworkSource: ArtworkPalette] = [:]

    init(loader: LibraryLoader, disk: ArtworkDiskCache = ArtworkDiskCache()) {
        self.loader = loader
        self.disk = disk
        cache.countLimit = 600
    }

    /// Changes when the source's art changed in Music; views key their loading on it.
    func revision(of source: ArtworkSource) -> Int { revisions[source] ?? 0 }

    func cachedImage(album: PersistentID, size: Size) -> NSImage? { cachedImage(.album(album), size: size) }
    func image(album: PersistentID, size: Size) async -> NSImage? { await image(.album(album), size: size) }
    func cachedPalette(album: PersistentID) -> ArtworkPalette? { palettes[.album(album)] }
    func palette(album: PersistentID) async -> ArtworkPalette? { await palette(.album(album)) }

    func cachedImage(_ source: ArtworkSource, size: Size) -> NSImage? {
        cache.object(forKey: Self.key(source, size))
    }

    func image(_ source: ArtworkSource, size: Size) async -> NSImage? {
        let key = Self.key(source, size)
        if let hit = cache.object(forKey: key) { return hit }
        if let task = inFlight[key] { return await task.value }

        let loader = self.loader, disk = self.disk
        // Thumbnails come from disk when one was saved for the art Music has now; launch shows them before
        // Music has even been read. Other sizes always come from Music.
        let label = size == .thumbnail ? currentLabel(source) : nil
        let task = Task<NSImage?, Never> {
            if let label, let saved = await disk.image(for: source, label: label) {
                return NSImage(cgImage: saved, size: NSSize(width: saved.width, height: saved.height))
            }
            guard let data = await loader.artworkData(for: source) else { return nil }
            guard let cg = await Self.decode(data, maxPixel: size.rawValue) else { return nil }
            if let label { Task.detached(priority: .utility) { await disk.store(cg, for: source, label: label) } }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    func cachedPalette(_ source: ArtworkSource) -> ArtworkPalette? { palettes[source] }

    /// Art that changed in Music: forget every size, its colours and its saved thumbnail, and bump its revision
    /// so covers on screen load the new art.
    func invalidate(_ sources: Set<ArtworkSource>) {
        guard !sources.isEmpty else { return }
        for source in sources {
            for size in [Size.thumbnail, .large, .full] {
                cache.removeObject(forKey: Self.key(source, size))
                inFlight[Self.key(source, size)] = nil
            }
            palettes[source] = nil
            BackdropImages.forget(source)
            revisions[source, default: 0] += 1
        }
        let disk = self.disk
        Task.detached(priority: .utility) { for source in sources { await disk.remove(source) } }
    }

    /// After a read of Music: drop saved thumbnails for art that changed or went away while Beat wasn't looking.
    func pruneSavedThumbnails(keeping library: LibrarySnapshot) {
        let disk = self.disk
        Task.detached(priority: .utility) { await disk.prune(keeping: library) }
    }

    /// Music access was lost: nothing from the library stays on disk.
    func removeSavedThumbnails() {
        let disk = self.disk
        Task.detached(priority: .utility) { await disk.removeAll() }
    }

    /// Whether two sources show the same picture: tracks of one release often each embed the same cover,
    /// and Now Playing shouldn't cross-fade between identical art. Compares the decoded thumbnails' pixels.
    func samePicture(_ a: ArtworkSource, _ b: ArtworkSource) async -> Bool {
        if a == b { return true }
        guard let x = await image(a, size: .thumbnail)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let y = await image(b, size: .thumbnail)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              x.width == y.width, x.height == y.height,
              let dx = x.dataProvider?.data as Data?, let dy = y.dataProvider?.data as Data? else { return false }
        return dx == dy
    }

    /// The art's colours, extracted off the main actor from the thumbnail and cached per album or track.
    func palette(_ source: ArtworkSource) async -> ArtworkPalette? {
        if let hit = palettes[source] { return hit }
        guard let image = await image(source, size: .thumbnail),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let palette = await Self.extractPalette(cg)
        if let palette { palettes[source] = palette }
        return palette
    }

    @concurrent
    private nonisolated static func extractPalette(_ image: CGImage) async -> ArtworkPalette? {
        ArtworkPalette.extract(from: image)
    }

    @concurrent
    private nonisolated static func decode(_ data: Data, maxPixel: Int) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func key(_ source: ArtworkSource, _ size: Size) -> NSString {
        switch source {
        case .album(let id): "\(id)-\(size.rawValue)" as NSString
        case .track(let id): "t\(id)-\(size.rawValue)" as NSString
        }
    }
}
