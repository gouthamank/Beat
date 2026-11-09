import CoreGraphics
import SwiftUI

/// An sRGB colour with components in 0...1, kept as plain numbers so palette picking is pure and testable.
struct RGB: Hashable, Sendable {
    var r: Double
    var g: Double
    var b: Double

    static let white = RGB(r: 1, g: 1, b: 1)
    static let black = RGB(r: 0, g: 0, b: 0)

    /// WCAG relative luminance.
    var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// WCAG contrast ratio, from 1 (same) to 21 (black on white).
    func contrast(with other: RGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    func distance(to other: RGB) -> Double {
        ((r - other.r) * (r - other.r) + (g - other.g) * (g - other.g) + (b - other.b) * (b - other.b)).squareRoot()
    }

    /// This colour laid over `background` at `opacity`.
    func over(_ background: RGB, opacity: Double) -> RGB {
        RGB(r: r * opacity + background.r * (1 - opacity),
            g: g * opacity + background.g * (1 - opacity),
            b: b * opacity + background.b * (1 - opacity))
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}

/// Colours taken from an album cover, like iTunes 11's album view: a background the page continues from,
/// and text colours from the same cover that always stay readable on it.
struct ArtworkPalette: Equatable, Sendable {
    static let primaryContrast = 4.5   // WCAG AA for body text
    static let secondaryContrast = 3.0

    var background: RGB
    var primary: RGB
    var secondary: RGB

    /// White reads better than black on the background, so the page should use dark appearance.
    var isDark: Bool { background.contrast(with: .white) > background.contrast(with: .black) }

    /// Picks a palette from pixels and their weights (edge pixels count extra).
    static func make(pixels: [(color: RGB, weight: Double)]) -> ArtworkPalette {
        let clusters = cluster(pixels)
        guard let background = clusters.first?.color else {
            return ArtworkPalette(background: .black, primary: .white, secondary: RGB.white.over(.black, opacity: 0.7))
        }
        let candidates = clusters.dropFirst().map(\.color)

        let primary = candidates.first {
            $0.contrast(with: background) >= primaryContrast && $0.distance(to: background) > 0.2
        } ?? (background.contrast(with: .white) >= background.contrast(with: .black) ? .white : .black)

        let secondary = candidates.first {
            $0 != primary && $0.contrast(with: background) >= secondaryContrast
                && $0.distance(to: background) > 0.2 && $0.distance(to: primary) > 0.1
        } ?? {
            // A softer primary, unless softening it would drop below the secondary minimum.
            let soft = primary.over(background, opacity: 0.7)
            return soft.contrast(with: background) >= secondaryContrast ? soft : primary
        }()

        return ArtworkPalette(background: background, primary: primary, secondary: secondary)
    }

    /// Buckets colours (4 bits per channel), then merges near-identical buckets so one colour's shading
    /// counts as one colour. Sorted by total weight, heaviest first.
    static func cluster(_ pixels: [(color: RGB, weight: Double)]) -> [(color: RGB, weight: Double)] {
        var buckets: [Int: (sum: RGB, weight: Double)] = [:]
        for (c, w) in pixels where w > 0 {
            let key = Int(c.r * 15.99) << 8 | Int(c.g * 15.99) << 4 | Int(c.b * 15.99)
            var entry = buckets[key] ?? (RGB.black, 0)
            entry.sum = RGB(r: entry.sum.r + c.r * w, g: entry.sum.g + c.g * w, b: entry.sum.b + c.b * w)
            entry.weight += w
            buckets[key] = entry
        }
        let averaged = buckets.values
            .map { (color: RGB(r: $0.sum.r / $0.weight, g: $0.sum.g / $0.weight, b: $0.sum.b / $0.weight), weight: $0.weight) }
            .sorted { $0.weight > $1.weight }

        var clusters: [(color: RGB, weight: Double)] = []
        for bucket in averaged {
            if let i = clusters.firstIndex(where: { $0.color.distance(to: bucket.color) < 0.12 }) {
                clusters[i].weight += bucket.weight
            } else {
                clusters.append(bucket)
            }
        }
        return clusters.sorted { $0.weight > $1.weight }
    }

    /// Shrinks the cover to 24×24 and picks from its pixels; the outer ring counts three times.
    static func extract(from image: CGImage) -> ArtworkPalette? {
        let side = 24
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }

        var pixels: [(color: RGB, weight: Double)] = []
        pixels.reserveCapacity(side * side)
        for y in 0..<side {
            for x in 0..<side {
                let i = (y * side + x) * 4
                let alpha = Double(bytes[i + 3]) / 255
                guard alpha > 0.5 else { continue }
                func channel(_ v: UInt8) -> Double { min(Double(v) / 255 / alpha, 1) }
                let color = RGB(r: channel(bytes[i]), g: channel(bytes[i + 1]), b: channel(bytes[i + 2]))
                let isEdge = x == 0 || y == 0 || x == side - 1 || y == side - 1
                pixels.append((color, isEdge ? 3 : 1))
            }
        }
        return make(pixels: pixels)
    }
}
