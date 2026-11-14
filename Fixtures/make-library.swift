// Writes Fixtures/Library: the songs UI tests play (`-BeatFixtureLibrary`, see TESTING.md), so they never need the
// real library. The same nine albums as the snapshot tests' `SnapshotLibrary`: short tones in tagged .m4a files, each
// album with its own flat-coloured cover. The output is committed; run this again only to change it, from the repo
// root: `swift Fixtures/make-library.swift`.
import AVFoundation
import CoreGraphics
import ImageIO

struct AlbumSpec {
    let title: String
    let artist: String
    let genre: String
    let year: Int
    let songs: [String]
    /// The cover's hue, 0...1.
    let hue: CGFloat
}

let albums: [AlbumSpec] = [
    AlbumSpec(title: "Northern Lights", artist: "Aurora Lane", genre: "Electronic", year: 2019,
              songs: ["Arrival", "Polar Night", "Glow", "Thaw"], hue: 0.55),
    AlbumSpec(title: "Low Sun", artist: "Aurora Lane", genre: "Electronic", year: 2022,
              songs: ["Dawn Chorus", "Long Shadows", "Ember"], hue: 0.08),
    AlbumSpec(title: "First Light", artist: "Aurora Lane", genre: "Ambient", year: 2015,
              songs: ["Haze", "Still Water", "Morning"], hue: 0.15),
    AlbumSpec(title: "Tin and Copper", artist: "Bronze Era", genre: "Rock", year: 2003,
              songs: ["Forge", "Alloy", "Rust Belt", "Patina", "Smelter"], hue: 0.04),
    AlbumSpec(title: "Second Casting", artist: "Bronze Era", genre: "Rock", year: 2008,
              songs: ["Mould", "Pour", "Temper"], hue: 0.95),
    AlbumSpec(title: "Deep Blue", artist: "Cobalt", genre: "Jazz", year: 1998,
              songs: ["Undertow", "Fathom", "Blue Hour", "Tidal"], hue: 0.62),
    AlbumSpec(title: "Pigment", artist: "Cobalt", genre: "Jazz", year: 2011,
              songs: ["Ultramarine", "Indigo", "Azure"], hue: 0.7),
    AlbumSpec(title: "Estuary", artist: "Delta Hours", genre: "Ambient", year: 2024,
              songs: ["Silt", "Reeds", "Slack Tide"], hue: 0.38),
    AlbumSpec(title: "Late Shift", artist: "Delta Hours", genre: "Jazz", year: 2017,
              songs: ["Clocking On", "Night Bus", "Neon"], hue: 0.8),
]

/// HSB to RGB at a fixed saturation, as `SnapshotLibrary` draws its covers.
func color(hue: CGFloat, brightness v: CGFloat) -> CGColor {
    let s: CGFloat = 0.6
    let h = hue * 6, i = Int(h) % 6, f = h - floor(h)
    let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
    let (r, g, b): (CGFloat, CGFloat, CGFloat) = switch i {
    case 0: (v, t, p)
    case 1: (q, v, p)
    case 2: (p, v, t)
    case 3: (p, q, v)
    case 4: (t, p, v)
    default: (v, p, q)
    }
    return CGColor(red: r, green: g, blue: b, alpha: 1)
}

/// A 300-pixel cover in one colour with a lighter band, as PNG.
func cover(hue: CGFloat) -> Data {
    let side = 300
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(color(hue: hue, brightness: 0.75))
    context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    context.setFillColor(color(hue: hue, brightness: 0.95))
    context.fill(CGRect(x: 0, y: side / 3, width: side, height: side / 6))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
}

/// Two seconds of a soft tone, faded in and out, as AAC.
func writeTone(to url: URL, frequency: Double) throws {
    let rate = 44_100.0, frames = AVAudioFrameCount(rate * 2)
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let samples = buffer.floatChannelData![0]
    for i in 0..<Int(frames) {
        let t = Double(i) / rate
        let fade = min(1, t / 0.1, (2 - t) / 0.1)
        samples[i] = Float(sin(2 * .pi * frequency * t) * 0.1 * fade)
    }
    let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate,
                                   AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32_000]
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

let root = URL(fileURLWithPath: "Fixtures/Library", isDirectory: true)
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("BeatFixtures-\(UUID().uuidString)")
try? FileManager.default.removeItem(at: root)
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)

var count = 0
for (albumIndex, album) in albums.enumerated() {
    let folder = root.appendingPathComponent(album.artist).appendingPathComponent(album.title)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let art = cover(hue: album.hue)
    for (index, title) in album.songs.enumerated() {
        let number = index + 1
        let raw = scratch.appendingPathComponent("\(albumIndex)-\(number).m4a")
        // A different note for every song, so tests can tell by ear which one is playing.
        try writeTone(to: raw, frequency: 220 * pow(2, Double(albumIndex * 3 + index) / 12))

        let export = AVAssetExportSession(asset: AVURLAsset(url: raw), presetName: AVAssetExportPresetPassthrough)!
        export.metadata = [
            item(.iTunesMetadataSongName, title as NSString),
            item(.iTunesMetadataArtist, album.artist as NSString),
            item(.iTunesMetadataAlbumArtist, album.artist as NSString),
            item(.iTunesMetadataAlbum, album.title as NSString),
            item(.iTunesMetadataUserGenre, album.genre as NSString),
            item(.iTunesMetadataReleaseDate, "\(album.year)" as NSString),
            item(.iTunesMetadataTrackNumber, Data([0, 0, 0, UInt8(number), 0, UInt8(album.songs.count), 0, 0]) as NSData,
                 type: kCMMetadataBaseDataType_RawData),
            item(.iTunesMetadataCoverArt, art as NSData, type: kCMMetadataBaseDataType_PNG),
        ]
        let destination = folder.appendingPathComponent(String(format: "%02d %@.m4a", number, title))
        try await export.export(to: destination, as: .m4a)
        count += 1
    }
}
try? FileManager.default.removeItem(at: scratch)
print("Wrote \(count) songs in \(albums.count) albums to \(root.path)")
