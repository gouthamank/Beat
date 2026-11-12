import SwiftUI

struct ArtworkView: View {
    let source: ArtworkSource?
    var size: ArtworkCache.Size = .thumbnail
    var cornerRadius: CGFloat = 8
    /// Square crops to fill, so grids line up. Original keeps the cover's own shape (some labels use
    /// wide covers), for places where the cover is the focus.
    var framing: Framing = .square

    enum Framing { case square, original }

    init(albumID: PersistentID?, size: ArtworkCache.Size = .thumbnail, cornerRadius: CGFloat = 8, framing: Framing = .square) {
        self.init(source: albumID.map { .album($0) }, size: size, cornerRadius: cornerRadius, framing: framing)
    }

    /// A track's own art (Now Playing), else its album's cover.
    init(track: Track, size: ArtworkCache.Size = .thumbnail, cornerRadius: CGFloat = 8, framing: Framing = .square) {
        self.init(source: ArtworkSource(track), size: size, cornerRadius: cornerRadius, framing: framing)
    }

    init(source: ArtworkSource?, size: ArtworkCache.Size = .thumbnail, cornerRadius: CGFloat = 8, framing: Framing = .square) {
        self.source = source
        self.size = size
        self.cornerRadius = cornerRadius
        self.framing = framing
    }

    @Environment(ArtworkCache.self) private var artwork
    @State private var image: NSImage?

    private struct Load: Hashable {
        let source: ArtworkSource?
        let size: ArtworkCache.Size
    }

    /// The loaded image, else anything already cached (a large request shows the cached thumbnail
    /// meanwhile), so a view never flashes the placeholder for art that's already in memory.
    private var shown: NSImage? {
        if let image { return image }
        guard let source else { return nil }
        return artwork.cachedImage(source, size: size)
            ?? (size == .large ? artwork.cachedImage(source, size: .thumbnail) : nil)
    }

    var body: some View {
        content
            // A new size loads too (Cover Flow sharpens the cover reaching the centre); the current image stays
            // up meanwhile, so nothing flashes.
            .task(id: Load(source: source, size: size)) {
                guard let source else { image = nil; return }
                if let cached = artwork.cachedImage(source, size: size) {
                    image = cached
                    return
                }
                let loaded = await artwork.image(source, size: size)
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
    }

    @ViewBuilder
    private var content: some View {
        if framing == .original, let image = shown {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .transition(.opacity)
        } else {
            square
        }
    }

    private var square: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.quaternary)
            .overlay {
                if let image = shown {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .aspectRatio(1, contentMode: .fit)
    }
}
