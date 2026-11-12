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
    @ObservationIgnored private let cache = NSCache<NSString, NSImage>()
    @ObservationIgnored private var inFlight: [NSString: Task<NSImage?, Never>] = [:]
    /// Small and few (one per album visited or track played), so a plain dictionary rather than NSCache.
    @ObservationIgnored private var palettes: [ArtworkSource: ArtworkPalette] = [:]

    init(loader: LibraryLoader) {
        self.loader = loader
        cache.countLimit = 600
    }

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

        let loader = self.loader
        let task = Task<NSImage?, Never> {
            guard let data = await loader.artworkData(for: source) else { return nil }
            guard let cg = await Self.decode(data, maxPixel: size.rawValue) else { return nil }
            return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { cache.setObject(image, forKey: key) }
        return image
    }

    func cachedPalette(_ source: ArtworkSource) -> ArtworkPalette? { palettes[source] }

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
