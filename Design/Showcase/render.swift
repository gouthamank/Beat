// The showcase library: made-up albums for the website's demo and screenshots, so no real album art is ever shown.
// `library.json` is written by hand (albums, artists, genres, years, song titles, each cover's style and colours); this
// fills in the rest the same way every run (durations, play counts, cover tints) from a seed per album. Songs are
// silent except a few given real, public-domain or CC0 music (Audio/, with synced lyrics in Lyrics/), so Now Playing,
// the visualizer and the website's play button have something to play.
//
// Run from the repo root:
//   swift Design/Showcase/render.swift
//       draws the covers into Design/Showcase/Covers and writes Design/Showcase/showcase.json, the website's data
//   swift Design/Showcase/render.swift --library <folder> --history <file>
//       instead writes, from those two, the songs as tagged, silent .m4a files for `-BeatFixtureLibrary` (each
//       album's cover embedded), and Beat's play history for them dated from now (either option alone works;
//       `make mac-run-showcase` uses both)
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

// MARK: - Input

struct Library: Decodable { let albums: [AlbumSpec] }

struct AlbumSpec: Decodable {
    let title: String
    let artist: String
    let genre: String
    let year: Int
    /// 0...1: how much it's been played, and how recently.
    let popularity: Double
    /// The comments tag on every song: one label's releases carry it with a catalog number, for custom sort fields.
    var comments: String?
    let cover: CoverSpec
    let songs: [SongSpec]
}

/// A song's title, or for one of the few with real music (the rest are silent), an object naming its audio file and
/// optionally an .lrc file of synced lyrics (both under Design/Showcase), and whom to credit.
struct SongSpec: Decodable {
    let title: String
    var audio: String?
    var lyrics: String?
    var credit: Credit?

    init(from decoder: any Decoder) throws {
        if let title = try? decoder.singleValueContainer().decode(String.self) {
            self.title = title
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        audio = try container.decodeIfPresent(String.self, forKey: .audio)
        lyrics = try container.decodeIfPresent(String.self, forKey: .lyrics)
        credit = try container.decodeIfPresent(Credit.self, forKey: .credit)
    }

    private enum CodingKeys: String, CodingKey { case title, audio, lyrics, credit }
}

/// The real recording behind a song with music, credited in the website's footer.
struct Credit: Codable {
    let title: String
    let artist: String
    let license: String
    let url: String
}

struct CoverSpec: Decodable {
    let style: String
    let colors: [String]
}

let showcase = URL(fileURLWithPath: "Design/Showcase", isDirectory: true)
let library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: showcase.appendingPathComponent("library.json")))

func option(_ name: String) -> URL? {
    let arguments = CommandLine.arguments
    guard let i = arguments.firstIndex(of: name), arguments.indices.contains(i + 1) else { return nil }
    return URL(fileURLWithPath: arguments[i + 1])
}

// MARK: - Seeds

/// FNV-1a, as `FolderLibrarySource.stableID`: the songs' IDs in the play history must be the ones Beat gives them.
func stableID(_ text: String) -> UInt64 {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
    return hash
}

/// SplitMix64, seeded per album, so a cover or a play count changes only when its own album does.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

func slug(_ text: String) -> String {
    text.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        .split(separator: "-").joined(separator: "-")
}

// MARK: - Songs

struct Song: Codable {
    let title: String
    let track: Int
    var duration: Int
    let plays: Int
    let skips: Int
    let lastPlayedDaysAgo: Double?
    let lastSkippedDaysAgo: Double?
    /// The path under the library folder, as Beat reads it ("/Artist/Album/01 Title.m4a"), which its ID is made from.
    let path: String
    /// For a song with real music: its audio and lyrics files, under Design/Showcase, and its credit.
    var audio: String?
    var lyrics: String?
    var credit: Credit?
}

/// Seconds per song by genre: a jazz take runs longer than a pop single.
let durations: [String: ClosedRange<Int>] = [
    "Electronic": 230...390, "Pop": 165...235, "Indie": 180...265, "Jazz": 270...470, "Ambient": 300...560,
    "Rock": 185...300, "Hip-Hop": 145...240, "Soul": 165...260, "Classical": 170...420, "Folk": 160...255,
]

/// A song with real music takes its audio's length; its made-up one is still drawn, so the songs after it keep theirs.
func songs(of album: AlbumSpec, rng: inout SeededRNG) async throws -> [Song] {
    var songs = album.songs.enumerated().map { index, spec in
        let title = spec.title
        let lower = title.lowercased()
        let isInterlude = lower.hasPrefix("intro") || lower.hasPrefix("outro") || lower.contains("introduction")
        let duration = isInterlude ? Int.random(in: 35...95, using: &rng)
            : Int.random(in: durations[album.genre] ?? 180...260, using: &rng)
        // The title track and the opener get played most; interludes least.
        var weight = Double.random(in: 0.25...1.1, using: &rng)
        if title == album.title { weight *= 1.6 }
        if index == 0 { weight *= 1.25 }
        if isInterlude { weight *= 0.3 }
        let plays = Int((album.popularity * album.popularity * 48 * weight).rounded())
        let skips = Double.random(in: 0...1, using: &rng) < 0.35 * (1.2 - album.popularity) ? Int.random(in: 1...4, using: &rng) : 0
        // Popular albums were played recently; a played song was last played within a span that grows as popularity falls.
        let span = (1 - album.popularity) * 320 + 6
        let lastPlayed = plays > 0 ? Double.random(in: 0...span, using: &rng) : nil
        let lastSkipped = skips > 0 ? Double.random(in: 0...span * 1.5, using: &rng) : nil
        let number = index + 1
        return Song(title: title, track: number, duration: duration, plays: plays, skips: skips,
                    lastPlayedDaysAgo: lastPlayed.map { ($0 * 10).rounded() / 10 },
                    lastSkippedDaysAgo: lastSkipped.map { ($0 * 10).rounded() / 10 },
                    path: "/\(album.artist)/\(album.title)/" + String(format: "%02d %@.m4a", number, title),
                    audio: spec.audio, lyrics: spec.lyrics, credit: spec.credit)
    }
    for i in songs.indices {
        guard let audio = songs[i].audio else { continue }
        let length = try await AVURLAsset(url: showcase.appendingPathComponent(audio)).load(.duration)
        songs[i].duration = Int(CMTimeGetSeconds(length).rounded())
    }
    return songs
}

// MARK: - Covers

let side = 800
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: String, alpha: CGFloat = 1) -> CGColor {
    let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
    return CGColor(colorSpace: sRGB, components: [CGFloat(value >> 16 & 0xFF) / 255, CGFloat(value >> 8 & 0xFF) / 255,
                                                  CGFloat(value & 0xFF) / 255, alpha])!
}

func gradient(_ hexes: [String]) -> CGGradient {
    let locations = hexes.indices.map { CGFloat($0) / CGFloat(max(hexes.count - 1, 1)) }
    return CGGradient(colorsSpace: sRGB, colors: hexes.map { color($0) } as CFArray, locations: locations)!
}

func makeContext() -> CGContext {
    CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// Each style draws on a context with the origin at the bottom left, in pixels. `c` is the album's four colours.
func draw(style: String, c: [String], in ctx: CGContext, rng: inout SeededRNG) -> CGImage {
    let s = CGFloat(side)
    let full = CGRect(x: 0, y: 0, width: s, height: s)
    func random(_ range: ClosedRange<CGFloat>) -> CGFloat { CGFloat.random(in: range, using: &rng) }

    switch style {
    case "gradient":
        // A diagonal wash through all four colours, with a soft light in one corner.
        let angle = random(0...(2 * .pi))
        let start = CGPoint(x: s / 2 + cos(angle) * s * 0.7, y: s / 2 + sin(angle) * s * 0.7)
        let end = CGPoint(x: s - start.x, y: s - start.y)
        ctx.drawLinearGradient(gradient(c), start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        let light = CGGradient(colorsSpace: sRGB, colors: [color("#FFFFFF", alpha: 0.35), color("#FFFFFF", alpha: 0)] as CFArray,
                               locations: [0, 1])!
        let center = CGPoint(x: random(0.15...0.85) * s, y: random(0.15...0.85) * s)
        ctx.drawRadialGradient(light, startCenter: center, startRadius: 0, endCenter: center, endRadius: s * 0.6, options: [])

    case "orb":
        // A sun over a sky: the sky from the first two colours, the sun from the last two, sometimes cut by bands
        // across its lower half.
        ctx.drawLinearGradient(gradient([c[1], c[0]]), start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: s), options: [])
        let radius = s * random(0.26...0.36)
        let center = CGPoint(x: s * random(0.4...0.6), y: s * random(0.42...0.58))
        let sun = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.saveGState()
        ctx.addEllipse(in: sun)
        ctx.clip()
        if Bool.random(using: &rng) {
            // The bands cut out of the sun: the whole square less the bands, even-odd, within the circle.
            ctx.addRect(full)
            var y = center.y - radius
            var gap: CGFloat = 4
            while y < center.y {
                ctx.addRect(CGRect(x: sun.minX, y: y, width: sun.width, height: gap))
                y += gap * 3.2
                gap += 3
            }
            ctx.clip(using: .evenOdd)
        }
        ctx.drawLinearGradient(gradient([c[2], c[3]]), start: CGPoint(x: 0, y: sun.minY), end: CGPoint(x: 0, y: sun.maxY), options: [])
        ctx.restoreGState()
        // A glow around it.
        let glow = CGGradient(colorsSpace: sRGB, colors: [color(c[2], alpha: 0.35), color(c[2], alpha: 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: center, startRadius: radius, endCenter: center, endRadius: radius * 1.9, options: [])

    case "overlap":
        // Three big flat circles printed over each other, like a risograph: where they cross, the inks mix (lighten
        // on a dark ground, darken on a light one).
        ctx.setFillColor(color(c[0]))
        ctx.fill(full)
        let ground = color(c[0]).components!
        let dark = 0.2126 * ground[0] + 0.7152 * ground[1] + 0.0722 * ground[2] < 0.5
        ctx.setBlendMode(dark ? .screen : .multiply)
        let middle = CGPoint(x: s * random(0.42...0.58), y: s * random(0.42...0.58))
        let start = random(0...(2 * .pi))
        for i in 0..<3 {
            let angle = start + CGFloat(i) * 2 * .pi / 3
            let r = s * random(0.24...0.32)
            let reach = s * random(0.12...0.2)
            let center = CGPoint(x: middle.x + cos(angle) * reach, y: middle.y + sin(angle) * reach)
            ctx.setFillColor(color(c[1 + i]))
            ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
        ctx.setBlendMode(.normal)

    case "rings":
        // Concentric rings off centre, in turn through the last three colours, on the first.
        ctx.setFillColor(color(c[0]))
        ctx.fill(full)
        let center = CGPoint(x: s * random(0.3...0.7), y: s * random(0.3...0.7))
        var radius = s * 0.95
        var i = 0
        while radius > s * 0.04 {
            ctx.setFillColor(color(i % 4 == 3 ? c[0] : c[1 + i % 4]))
            ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            radius -= s * random(0.03...0.09)
            i += 1
        }

    case "stripes":
        // Bands of the last three colours, level or tilted, on the first.
        ctx.setFillColor(color(c[0]))
        ctx.fill(full)
        ctx.translateBy(x: s / 2, y: s / 2)
        ctx.rotate(by: [0, .pi / 4, -.pi / 4, .pi / 2].randomElement(using: &rng)!)
        ctx.translateBy(x: -s, y: -s)
        var y: CGFloat = s * random(0.4...0.9)
        var i = 0
        while y < s * 1.6 {
            let height = s * random(0.03...0.12)
            ctx.setFillColor(color(c[1 + i % 3]))
            ctx.fill(CGRect(x: 0, y: y, width: s * 2, height: height))
            y += height + s * random(0.01...0.05)
            i += 1
        }

    case "bauhaus":
        // A two-by-two or three-by-three grid of flat shapes on paper (the first colour).
        ctx.setFillColor(color(c[0]))
        ctx.fill(full)
        let n = Bool.random(using: &rng) ? 2 : 3
        let cell = s / CGFloat(n)
        for row in 0..<n {
            for column in 0..<n {
                // Half a pixel over each edge, so two shapes of one colour meet without a seam.
                let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell).insetBy(dx: -0.5, dy: -0.5)
                let fill = color(c[1 + Int.random(in: 0...2, using: &rng)])
                ctx.setFillColor(fill)
                switch Int.random(in: 0...5, using: &rng) {
                case 0: ctx.fillEllipse(in: rect.insetBy(dx: cell * 0.08, dy: cell * 0.08))
                case 1:
                    // A quarter circle from one corner.
                    let corner = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                                  CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)].randomElement(using: &rng)!
                    ctx.saveGState()
                    ctx.clip(to: rect)
                    ctx.fillEllipse(in: CGRect(x: corner.x - cell, y: corner.y - cell, width: cell * 2, height: cell * 2))
                    ctx.restoreGState()
                case 2:
                    // A half circle on one edge.
                    ctx.saveGState()
                    ctx.clip(to: rect)
                    let up = Bool.random(using: &rng)
                    ctx.fillEllipse(in: CGRect(x: rect.minX, y: up ? rect.minY - cell / 2 : rect.midY, width: cell, height: cell))
                    ctx.restoreGState()
                case 3: ctx.fill(rect)
                case 4:
                    ctx.fill(rect)
                    ctx.setFillColor(color(c[0]))
                    ctx.fillEllipse(in: rect.insetBy(dx: cell * 0.22, dy: cell * 0.22))
                default: break
                }
            }
        }

    case "grid":
        // A halftone: dots that swell towards one corner, in two colours, on the first.
        ctx.setFillColor(color(c[0]))
        ctx.fill(full)
        let count = Int.random(in: 9...14, using: &rng)
        let step = s / CGFloat(count)
        let focus = CGPoint(x: random(0...1) * s, y: random(0...1) * s)
        for row in 0..<count {
            for column in 0..<count {
                let center = CGPoint(x: (CGFloat(column) + 0.5) * step, y: (CGFloat(row) + 0.5) * step)
                let distance = hypot(center.x - focus.x, center.y - focus.y) / (s * 1.2)
                let r = step * 0.48 * max(0.08, 1 - distance)
                ctx.setFillColor(color((row + column) % 5 == 0 ? c[3] : c[1 + (row / 3 + column / 3) % 2]))
                ctx.fillEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }
        }

    case "waves":
        // Layered hills or swells, from the first colour (sky) down to the last (foreground).
        ctx.setFillColor(color(c[0]))
        ctx.fill(full)
        for layer in 1..<4 {
            let base = s * (0.72 - CGFloat(layer) * 0.17)
            let amplitude = s * random(0.03...0.08)
            let frequency = random(1.2...3.2)
            let phase = random(0...(2 * .pi))
            ctx.beginPath()
            ctx.move(to: CGPoint(x: 0, y: 0))
            for x in stride(from: CGFloat(0), through: s, by: 4) {
                ctx.addLine(to: CGPoint(x: x, y: base + amplitude * sin(x / s * frequency * 2 * .pi + phase)))
            }
            ctx.addLine(to: CGPoint(x: s, y: 0))
            ctx.closePath()
            ctx.setFillColor(color(c[layer]))
            ctx.fillPath()
        }

    default:
        fatalError("Unknown cover style \(style)")
    }
    return ctx.makeImage()!
}

/// Fine film grain over the whole cover, so flat colour reads as printed rather than drawn.
func grained(_ image: CGImage, rng: inout SeededRNG) -> CGImage {
    let ctx = makeContext()
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    let pixels = ctx.data!.assumingMemoryBound(to: UInt8.self)
    for i in 0..<(side * side) {
        let noise = Int.random(in: -5...5, using: &rng)
        for channel in 0..<3 {
            let p = i * 4 + channel
            pixels[p] = UInt8(clamping: Int(pixels[p]) + noise)
        }
    }
    return ctx.makeImage()!
}

/// The colours Beat picks from a cover (`ArtworkPalette.extract`, copied here so the website's demo shows exactly
/// what the app would): the cover shrunk to 24×24, its pixels bucketed and merged (the outer ring counts three times),
/// the heaviest colour the background and the first that reads on it the primary, then a secondary.
struct Palette: Codable {
    let background: String
    let primary: String
    let secondary: String
}

func palette(of image: CGImage) -> Palette {
    struct RGB: Equatable {
        var r, g, b: Double
        var luminance: Double {
            func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        func contrast(with o: RGB) -> Double { (max(luminance, o.luminance) + 0.05) / (min(luminance, o.luminance) + 0.05) }
        func distance(to o: RGB) -> Double { ((r - o.r) * (r - o.r) + (g - o.g) * (g - o.g) + (b - o.b) * (b - o.b)).squareRoot() }
        func over(_ bg: RGB, opacity a: Double) -> RGB { RGB(r: r * a + bg.r * (1 - a), g: g * a + bg.g * (1 - a), b: b * a + bg.b * (1 - a)) }
        var hex: String { String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded())) }
        static let white = RGB(r: 1, g: 1, b: 1), black = RGB(r: 0, g: 0, b: 0)
    }
    let side = 24
    var bytes = [UInt8](repeating: 0, count: side * side * 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    }
    var pixels: [(color: RGB, weight: Double)] = []
    for y in 0..<side {
        for x in 0..<side {
            let i = (y * side + x) * 4
            let alpha = Double(bytes[i + 3]) / 255
            guard alpha > 0.5 else { continue }
            func channel(_ v: UInt8) -> Double { min(Double(v) / 255 / alpha, 1) }
            let isEdge = x == 0 || y == 0 || x == side - 1 || y == side - 1
            pixels.append((RGB(r: channel(bytes[i]), g: channel(bytes[i + 1]), b: channel(bytes[i + 2])), isEdge ? 3 : 1))
        }
    }
    // Buckets of 4 bits a channel, then near-identical buckets merged, heaviest first.
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
    clusters.sort { $0.weight > $1.weight }
    let background = clusters.first?.color ?? .black
    let candidates = clusters.dropFirst().map(\.color)
    let primary = candidates.first { $0.contrast(with: background) >= 4.5 && $0.distance(to: background) > 0.2 }
        ?? (background.contrast(with: .white) >= background.contrast(with: .black) ? .white : .black)
    let secondary = candidates.first {
        $0 != primary && $0.contrast(with: background) >= 3 && $0.distance(to: background) > 0.2 && $0.distance(to: primary) > 0.1
    } ?? {
        let soft = primary.over(background, opacity: 0.7)
        return soft.contrast(with: background) >= 3 ? soft : primary
    }()
    return Palette(background: background.hex, primary: primary.hex, secondary: secondary.hex)
}

/// The cover's average colour, as hex: the website tints the demo's now-playing bar with it, as Beat does.
func tint(of image: CGImage) -> String {
    let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .medium
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    let p = ctx.data!.assumingMemoryBound(to: UInt8.self)
    return String(format: "#%02X%02X%02X", p[0], p[1], p[2])
}

func jpeg(_ image: CGImage) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
    CGImageDestinationFinalize(destination)
    return data as Data
}

// MARK: - Website data

struct Album: Codable {
    let id: String
    let title: String
    let artist: String
    let genre: String
    let year: Int
    let cover: String
    let tint: String
    /// The cover's four colours, as drawn.
    let colors: [String]
    /// The colours Beat picks from the cover, for album pages, Now Playing and the bar.
    let palette: Palette
    let addedDaysAgo: Int
    var comments: String?
    let songs: [Song]
}

let coversFolder = showcase.appendingPathComponent("Covers", isDirectory: true)
let showcaseFile = showcase.appendingPathComponent("showcase.json")
/// Writing songs or history reads the committed covers and showcase.json rather than drawing them again.
let writesFiles = option("--library") != nil || option("--history") != nil

var albums: [Album] = []
if writesFiles {
    albums = try JSONDecoder().decode([String: [Album]].self, from: Data(contentsOf: showcaseFile))["albums"]!
} else {
    try? FileManager.default.removeItem(at: coversFolder)
    try FileManager.default.createDirectory(at: coversFolder, withIntermediateDirectories: true)
    for spec in library.albums {
        precondition(spec.cover.colors.count == 4, "\(spec.title) needs four cover colours")
        let id = slug("\(spec.artist) \(spec.title)")
        var rng = SeededRNG(state: stableID(id))
        let image = grained(draw(style: spec.cover.style, c: spec.cover.colors, in: makeContext(), rng: &rng), rng: &rng)
        try jpeg(image).write(to: coversFolder.appendingPathComponent("\(id).jpg"))
        // Albums from the last two years were added lately; the rest over the past few years.
        let added = spec.year >= 2025 ? Int.random(in: 1...40, using: &rng) : Int.random(in: 60...1100, using: &rng)
        albums.append(Album(id: id, title: spec.title, artist: spec.artist, genre: spec.genre, year: spec.year,
                            cover: "Covers/\(id).jpg", tint: tint(of: image), colors: spec.cover.colors, palette: palette(of: image), addedDaysAgo: added,
                            comments: spec.comments, songs: try await songs(of: spec, rng: &rng)))
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(["albums": albums]).write(to: showcaseFile)
    print("Drew \(albums.count) covers and wrote showcase.json (\(albums.reduce(0) { $0 + $1.songs.count }) songs)")
}

// MARK: - Beat's play history

/// `PlayHistoryStore.Stats`, encoded as Beat encodes it (a dictionary keyed by song ID).
struct Stats: Codable {
    var playCount = 0
    var lastPlayed: Date?
    var skipCount = 0
    var lastSkipped: Date?
}

if let historyFile = option("--history") {
    let now = Date()
    var history: [UInt64: Stats] = [:]
    for song in albums.flatMap(\.songs) where song.plays > 0 || song.skips > 0 {
        history[stableID(song.path)] = Stats(playCount: song.plays, lastPlayed: song.lastPlayedDaysAgo.map { now - $0 * 86_400 },
                                             skipCount: song.skips, lastSkipped: song.lastSkippedDaysAgo.map { now - $0 * 86_400 })
    }
    try FileManager.default.createDirectory(at: historyFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(history).write(to: historyFile)
    print("Wrote play history for \(history.count) songs to \(historyFile.path)")
}

// MARK: - Songs as files

/// Silence of the song's length as AAC: 8 kHz mono at 8 kbit/s is about 6 KB a minute, and Beat reads the duration
/// from the file.
func writeSilence(seconds: Int, to url: URL) throws {
    let rate = 8_000.0
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
    let frames = AVAudioFrameCount(rate * Double(seconds))
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                                   AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 8_000]
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    try file.write(from: buffer)
    file.close()
}

func item(_ identifier: AVMetadataIdentifier, _ value: any NSCopying & NSObjectProtocol, type: CFString? = nil) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.identifier = identifier
    item.value = value
    if let type { item.dataType = type as String }
    return item
}

if let root = option("--library") {
    let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("BeatShowcase-\(UUID().uuidString)")
    try? FileManager.default.removeItem(at: root)
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    var count = 0
    for album in albums {
        let cover = try Data(contentsOf: showcase.appendingPathComponent(album.cover))
        for song in album.songs {
            // A song with real music is encoded to AAC from its file (an MP3 can't pass through into .m4a); the rest
            // are silence. Either way the tags set here replace the file's own, so the real recording's names don't show.
            let export: AVAssetExportSession
            if let audio = song.audio {
                export = AVAssetExportSession(asset: AVURLAsset(url: showcase.appendingPathComponent(audio)),
                                              presetName: AVAssetExportPresetAppleM4A)!
            } else {
                let raw = scratch.appendingPathComponent("\(count).m4a")
                try writeSilence(seconds: song.duration, to: raw)
                export = AVAssetExportSession(asset: AVURLAsset(url: raw), presetName: AVAssetExportPresetPassthrough)!
            }
            export.metadata = [
                item(.iTunesMetadataSongName, song.title as NSString),
                item(.iTunesMetadataArtist, album.artist as NSString),
                item(.iTunesMetadataAlbumArtist, album.artist as NSString),
                item(.iTunesMetadataAlbum, album.title as NSString),
                item(.iTunesMetadataUserGenre, album.genre as NSString),
                item(.iTunesMetadataReleaseDate, "\(album.year)" as NSString),
                item(.iTunesMetadataTrackNumber, Data([0, 0, 0, UInt8(song.track), 0, UInt8(album.songs.count), 0, 0]) as NSData,
                     type: kCMMetadataBaseDataType_RawData),
                item(.iTunesMetadataCoverArt, cover as NSData, type: kCMMetadataBaseDataType_JPEG),
            ] + (album.comments.map { [item(.iTunesMetadataUserComment, $0 as NSString)] } ?? [])
            let destination = root.appendingPathComponent(String(song.path.dropFirst()))
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await export.export(to: destination, as: .m4a)
            // Beat reads synced lyrics from an .lrc file named after the song, beside it.
            if let lyrics = song.lyrics {
                try FileManager.default.copyItem(at: showcase.appendingPathComponent(lyrics),
                                                 to: destination.deletingPathExtension().appendingPathExtension("lrc"))
            }
            count += 1
        }
    }
    try? FileManager.default.removeItem(at: scratch)
    print("Wrote \(count) songs to \(root.path)")
}
