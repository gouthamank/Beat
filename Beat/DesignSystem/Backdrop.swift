import CoreImage
import SwiftUI

/// A heavily blurred copy of album art that glass surfaces above it pick up color from.
struct ArtworkBackdrop: View {
    enum Vividness {
        /// Muted, washed with the window colour.
        case subtle
        /// Strong colour, for pages coloured from their artwork.
        case vivid
    }

    let source: ArtworkSource?
    var vividness: Vividness = .subtle

    init(albumID: PersistentID?, vividness: Vividness = .subtle) {
        self.init(source: albumID.map { .album($0) }, vividness: vividness)
    }

    init(source: ArtworkSource?, vividness: Vividness = .subtle) {
        self.source = source
        self.vividness = vividness
    }

    @Environment(ArtworkCache.self) private var artwork
    @State private var image: NSImage?

    private var key: BackdropImages.Key? { source.map { .init(source: $0, vivid: vividness == .vivid) } }

    /// The rendered image, else one already cached, so the backdrop never flashes empty when revisited.
    private var shown: NSImage? { image ?? key.flatMap(BackdropImages.cached) }

    var body: some View {
        let vivid = vividness == .vivid
        Rectangle()
            .fill(.quaternary)
            .overlay {
                if let shown {
                    Image(nsImage: shown)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipped()
            .aspectRatio(1, contentMode: .fill)
            .opacity(vivid ? 0.9 : 0.55)
            .overlay(Color(nsColor: .windowBackgroundColor).opacity(vivid ? 0 : 0.35))
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .task(id: key) {
                guard let key else { image = nil; return }
                if let cached = BackdropImages.cached(key) { image = cached; return }
                let rendered = await BackdropImages.image(key, artwork: artwork)
                withAnimation(.easeOut(duration: 0.2)) { image = rendered }
            }
    }
}

/// Backdrops blurred and saturated once, into a small image that's scaled up. A live `.blur` over the
/// whole window was redrawn on every scrolled frame of an album page, under everything else on it.
@MainActor
enum BackdropImages {
    struct Key: Hashable, Sendable {
        let source: ArtworkSource
        let vivid: Bool
    }

    private static let cache = NSCache<NSString, NSImage>()

    static func cached(_ key: Key) -> NSImage? { cache.object(forKey: name(key)) }

    static func image(_ key: Key, artwork: ArtworkCache) async -> NSImage? {
        if let hit = cached(key) { return hit }
        guard let art = await artwork.image(key.source, size: .thumbnail),
              let cg = art.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let vivid = key.vivid
        guard let rendered = await Task.detached(priority: .userInitiated, operation: {
            render(cg, blur: vivid ? 60 : 80, saturation: vivid ? 1.9 : 1.4)
        }).value else { return nil }
        let image = NSImage(cgImage: rendered, size: NSSize(width: rendered.width, height: rendered.height))
        cache.setObject(image, forKey: name(key))
        return image
    }

    private static func name(_ key: Key) -> NSString { "\(key.source)-\(key.vivid)" as NSString }

    /// Pixels on the rendered image's long side. It's mostly blur, so scaling it up loses nothing.
    private nonisolated static let side: CGFloat = 96
    /// About how wide the backdrop shows, in points, so `blur` (the radius the live blur used) keeps
    /// the same softness at the small size.
    private nonisolated static let shownWidth: CGFloat = 1200
    private nonisolated static let context = CIContext()

    nonisolated static func render(_ cg: CGImage, blur: CGFloat, saturation: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: cg)
        let scale = side / max(input.extent.width, input.extent.height, 1)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = small.extent.integral
        // Clamped first so the edges stay opaque instead of fading to clear, as `.blur(opaque: true)` did.
        let output = small.clampedToExtent()
            .applyingGaussianBlur(sigma: blur * side / shownWidth)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation])
            .cropped(to: extent)
        return context.createCGImage(output, from: extent)
    }
}
