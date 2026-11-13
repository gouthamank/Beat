import SwiftUI

/// An artist's art: their photo from Discogs when one has been downloaded, else up to four of their covers
/// in a 2×2 square, newest first. One cover fills the square; two or three repeat to fill it. Which one is
/// decided by `ArtistImages`, so every copy (tile, header, the zoom's flying copy) draws the same thing.
struct ArtistArtwork: View {
    /// The artist's albums, newest first.
    let albumIDs: [PersistentID]
    /// The artist's ID, for their downloaded photo; nil shows the mosaic only.
    var artistID: String?
    var cornerRadius: CGFloat = 10
    @Environment(ArtistImages.self) private var images: ArtistImages?

    var body: some View {
        // One view that never changes, with the photo-or-mosaic choice inside it. Modifiers on a Group
        // apply to each branch, so a probe on this view lived on the mosaic and was lost when a first
        // download swapped in the photo; zooms from that tile then failed until it was rebuilt.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let artistID, let photo = images?.photo(for: artistID) {
                    Image(platformImage: photo).resizable().scaledToFill()
                } else {
                    mosaic
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var mosaic: some View {
        let covers = Array(albumIDs.prefix(4))
        if covers.count <= 1 {
            ArtworkView(albumID: covers.first, cornerRadius: 0)
        } else {
            Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ArtworkView(albumID: covers[0], cornerRadius: 0)
                    ArtworkView(albumID: covers[1 % covers.count], cornerRadius: 0)
                }
                GridRow {
                    // Two covers sit diagonally; three repeat the newest.
                    ArtworkView(albumID: covers.count == 2 ? covers[1] : covers[2], cornerRadius: 0)
                    ArtworkView(albumID: covers.count == 4 ? covers[3] : covers[0], cornerRadius: 0)
                }
            }
        }
    }
}

/// What represents each artist: their downloaded photo, or (nil) their cover mosaic. One answer per artist,
/// worked out the first time any view asks and shared by every view after, so a tile, the page header and
/// the zoom's flying copy always agree, and none of them changes what it shows after appearing.
///
/// Answering is synchronous and cheap: a file-exists check, and `PlatformImage(byReferencing:)`, which only
/// decodes the photo when it's first drawn.
@MainActor
@Observable
final class ArtistImages {
    private struct Answer {
        let image: PlatformImage?
        /// The photo file's date, so a refresh can tell whether anything actually changed.
        let modified: Date?
    }

    /// Bumped only when an answer really changes, so views showing artists ask again.
    private var version = 0
    @ObservationIgnored private var answers: [String: Answer] = [:]
    @ObservationIgnored private let directory: URL?

    init(directory: URL? = ArtistInfoProvider.defaultDirectory) {
        self.directory = directory
    }

    func photo(for artistID: String) -> PlatformImage? {
        _ = version
        if let answer = answers[artistID] { return answer.image }
        let answer = look(artistID)
        answers[artistID] = answer
        return answer.image
    }

    /// A photo may have been downloaded or replaced ("Wrong artist?"): look again. Artist pages call this on
    /// every visit, so an unchanged photo must change nothing: a new image (and every artist view
    /// re-rendering) in the middle of a zoom broke the transition.
    func refresh(_ artistID: String) {
        let answer = look(artistID)
        if let old = answers[artistID], old.modified == answer.modified { return }
        answers[artistID] = answer
        version += 1
    }

    /// Downloaded photos were cleared: every artist is back to the mosaic.
    func clear() {
        answers = [:]
        version += 1
    }

    private func look(_ artistID: String) -> Answer {
        guard let url = ArtistInfoProvider.photoURL(forKey: artistID, in: directory),
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return Answer(image: nil, modified: nil)
        }
        return Answer(image: PlatformImage.referencing(url), modified: attributes[.modificationDate] as? Date ?? .distantPast)
    }
}

extension Artist {
    /// Library order is oldest first within an artist; art and the artist page lead with the newest.
    var albumIDsNewestFirst: [PersistentID] { albumIDs.reversed() }
}
