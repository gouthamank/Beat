import ImageIO
import SnapshotTesting
import SwiftUI
import XCTest
@testable import Beat
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A small made-up library for snapshots: nine albums by five artists across four genres and three decades, each
/// album with its own flat-coloured cover. Fixed, so a snapshot changes only when a view does.
enum SnapshotLibrary {
    /// The moment snapshots are taken at, for anything that counts back from now.
    static let now = ISO8601DateFormatter().date(from: "2026-06-15T12:00:00Z")!

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private struct AlbumSpec {
        let id: PersistentID
        let title: String
        let artist: String
        let genre: String
        let year: Int
        let songs: [String]
        /// The cover's hue, 0...1.
        let hue: CGFloat
    }

    private static let albums: [AlbumSpec] = [
        AlbumSpec(id: 101, title: "Northern Lights", artist: "Aurora Lane", genre: "Electronic", year: 2019,
                  songs: ["Arrival", "Polar Night", "Glow", "Thaw"], hue: 0.55),
        AlbumSpec(id: 102, title: "Low Sun", artist: "Aurora Lane", genre: "Electronic", year: 2022,
                  songs: ["Dawn Chorus", "Long Shadows", "Ember"], hue: 0.08),
        AlbumSpec(id: 103, title: "First Light", artist: "Aurora Lane", genre: "Ambient", year: 2015,
                  songs: ["Haze", "Still Water", "Morning"], hue: 0.15),
        AlbumSpec(id: 104, title: "Tin and Copper", artist: "Bronze Era", genre: "Rock", year: 2003,
                  songs: ["Forge", "Alloy", "Rust Belt", "Patina", "Smelter"], hue: 0.04),
        AlbumSpec(id: 105, title: "Second Casting", artist: "Bronze Era", genre: "Rock", year: 2008,
                  songs: ["Mould", "Pour", "Temper"], hue: 0.95),
        AlbumSpec(id: 106, title: "Deep Blue", artist: "Cobalt", genre: "Jazz", year: 1998,
                  songs: ["Undertow", "Fathom", "Blue Hour", "Tidal"], hue: 0.62),
        AlbumSpec(id: 107, title: "Pigment", artist: "Cobalt", genre: "Jazz", year: 2011,
                  songs: ["Ultramarine", "Indigo", "Azure"], hue: 0.7),
        AlbumSpec(id: 108, title: "Estuary", artist: "Delta Hours", genre: "Ambient", year: 2024,
                  songs: ["Silt", "Reeds", "Slack Tide"], hue: 0.38),
        AlbumSpec(id: 109, title: "Late Shift", artist: "Delta Hours", genre: "Jazz", year: 2017,
                  songs: ["Clocking On", "Night Bus", "Neon"], hue: 0.8),
    ]

    static let tracks: [Track] = albums.flatMap { album in
        album.songs.enumerated().map { index, title in
            let id = album.id * 100 + PersistentID(index + 1)
            var track = Track.fixture(
                id: id, title: title, album: album.title, albumID: album.id, artist: album.artist,
                track: index + 1, hasArtwork: true, genre: album.genre, year: album.year,
                rating: (index * 20 + Int(album.id)) % 120 / 20 * 20, playCount: (Int(id) * 7) % 23,
                duration: TimeInterval(150 + (Int(id) * 37) % 200),
                dateAdded: now.addingTimeInterval(-Double(album.id - 100) * 30 * 86_400)
            )
            track.location = URL(string: "ipod-library://item/\(id)")!
            track.fileSize = 6_000_000 + Int64(id % 100) * 750_000
            return track
        }
    }

    static let snapshot = LibrarySnapshot.build(tracks: tracks)

    /// Every album's cover, and each song's (the album's), as PNG data for `FakeLibrarySource`.
    static var art: [ArtworkSource: Data] {
        var art: [ArtworkSource: Data] = [:]
        for album in albums {
            let png = cover(hue: album.hue)
            art[.album(album.id)] = png
            for track in tracks where track.albumID == album.id { art[.track(track.id)] = png }
        }
        return art
    }

    /// A cover in one colour with a lighter band, so tiles read as pictures rather than blocks.
    private static func cover(hue: CGFloat) -> Data {
        let side = 600
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

    private static func color(hue: CGFloat, brightness: CGFloat) -> CGColor {
        // HSB to RGB at a fixed saturation, without platform colour types.
        let s: CGFloat = 0.6, v = brightness
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

    /// The filter's result over this library, as a page would show it.
    static func result(_ filter: SmartFilter) -> FilterResult {
        SmartFilterEngine.evaluate(filter, in: PreparedLibrary(snapshot: snapshot, now: now, calendar: calendar))
    }
}

/// Every store a view reads, as `BeatApp.withStores` provides them, over `SnapshotLibrary`: nothing on disk, no
/// network, no system Now Playing, and settings of its own. Keep the list in step with `BeatApp.withStores`.
@MainActor
final class SnapshotStores {
    let defaults: UserDefaults
    let library: LibraryStore
    let artwork: ArtworkCache
    let history = PlayHistoryStore(fileURL: nil)
    let queue: PlaybackQueue
    let pages = PageStore(directory: nil)
    let navigator: AppNavigator
    let hero = HeroTransition()
    let lyrics = LyricsProvider(directory: nil)
    let artistInfo = ArtistInfoProvider(directory: nil)
    let artistImages = ArtistImages(directory: nil)
    let scrobbler: Scrobbler

    private init(defaults: UserDefaults, folder: URL) {
        self.defaults = defaults
        let source = FakeLibrarySource([.success(SnapshotLibrary.snapshot)], art: SnapshotLibrary.art)
        library = LibraryStore(loader: source, cacheDirectory: folder, libraryStamp: { nil })
        artwork = ArtworkCache(loader: source, disk: ArtworkDiskCache(directory: folder.appendingPathComponent("Thumbnails")))
        queue = PlaybackQueue(history: history, artwork: artwork, player: FakePlayer(), defaults: defaults,
                              publishesNowPlaying: false)
        navigator = AppNavigator(defaults: defaults)
        navigator.coverTint.configure(library: library, history: history, artwork: artwork)
        // Its setting is read from Beat's own defaults, which snapshots mustn't depend on.
        navigator.coverTint.isEnabled = { true }
        scrobbler = Scrobbler(credentials: nil, fileURL: nil, defaults: defaults,
                              storage: .init(load: { nil }, save: { _ in }))
    }

    /// Loaded, with every cover and its colours already in memory, so views draw them on their first pass.
    static func make(for test: XCTestCase) async throws -> SnapshotStores {
        let stores = SnapshotStores(defaults: test.temporaryDefaults(), folder: try test.temporaryFolder())
        await stores.library.load()
        for source in SnapshotLibrary.art.keys {
            for size in [ArtworkCache.Size.thumbnail, .large] { _ = await stores.artwork.image(source, size: size) }
            _ = await stores.artwork.palette(source)
        }
        return stores
    }

    func provide<Content: View>(_ content: Content) -> some View {
        content
            .environment(library)
            .environment(artwork)
            .environment(history)
            .environment(queue)
            .environment(pages)
            .environment(navigator)
            .environment(hero)
            .environment(\.lyricsProvider, lyrics)
            .environment(\.artistInfoProvider, artistInfo)
            .environment(artistImages)
            .environment(scrobbler)
            .defaultAppStorage(defaults)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.timeZone, SnapshotLibrary.calendar.timeZone)
            .environment(\.calendar, SnapshotLibrary.calendar)
            #if os(macOS)
            // The offscreen window is never key, so lists drew as in a window in the background (grey rows).
            .environment(\.controlActiveState, .key)
            #endif
    }
}

/// The widths views are snapshotted at.
enum SnapshotDevice: String, CaseIterable {
    case mac, iPad, iPhone

    var width: CGFloat {
        switch self {
        case .mac: 1000
        case .iPad: 820
        case .iPhone: 393
        }
    }

    /// For whole screens: the Mac's page column, an iPad in portrait, an iPhone.
    var height: CGFloat {
        switch self {
        case .mac: 760
        case .iPad: 1180
        case .iPhone: 852
        }
    }

    /// The devices this platform's tests render: the Mac's own, or the iPad's and iPhone's.
    static var current: [SnapshotDevice] {
        #if os(macOS)
        [.mac]
        #else
        [.iPad, .iPhone]
        #endif
    }
}

extension XCTestCase {
    /// Snapshots `view` at each device's width (or `width`) and its own height (or the device's, for a `fullScreen`
    /// view), in light and dark, against reference images in `__Snapshots__` beside the test. A missing reference is
    /// recorded and the test fails once; run it again. To re-record the ones that changed, check them by eye, then
    /// `make test-record` (or `ios-test-record`); `record: true` re-records this test's every time.
    @MainActor
    func assertScreens<V: View>(_ view: V, stores: SnapshotStores, fullScreen: Bool = false, width: CGFloat? = nil,
                                record: Bool = false,
                                file: StaticString = #filePath, testName: String = #function, line: UInt = #line) {
        for device in SnapshotDevice.current {
            for scheme in [ColorScheme.light, .dark] {
                let height: CGFloat? = fullScreen ? device.height : nil
                let width = width ?? device.width
                let root = stores.provide(
                    view
                        .environment(\.compactLayout, device == .iPhone)
                        .frame(width: width, height: height)
                        // A page asks its elements for their natural height (they sit in a vertical scroll view);
                        // offered the window's height, shelves and lists took all of it.
                        .fixedSize(horizontal: false, vertical: height == nil)
                        .background(.background)
                        .environment(\.colorScheme, scheme)
                )
                let host = SettledHost(root, width: width, height: height, scheme: scheme, compact: device == .iPhone)
                let name = "\(device.rawValue)-\(scheme == .dark ? "dark" : "light")"
                // Nil leaves the mode to SNAPSHOT_TESTING_RECORD (`make test-record` sets it to `failed`), else missing.
                withSnapshotTesting(record: record ? .all : nil) {
                    #if os(macOS)
                    assertSnapshot(of: host.view, as: .image(precision: 0.99, perceptualPrecision: 0.98),
                                   named: name, file: file, testName: testName, line: line)
                    #else
                    // Captured here rather than by the library: its own window gave navigation bars no side margins
                    // (large titles against the edge).
                    assertSnapshot(of: host.image(), as: .image(precision: 0.99, perceptualPrecision: 0.98, scale: 1),
                                   named: name, file: file, testName: testName, line: line)
                    #endif
                }
                host.close()
            }
        }
    }
}

/// A view hosted in an offscreen window and given time to settle before it's measured and captured: shelves and lists
/// measure their width on the first pass and only then fill in, so a view captured straight away came out empty.
@MainActor
private final class SettledHost<Content: View> {
    #if os(macOS)
    let controller: NSHostingController<Content>
    private let window: NSWindow
    var view: NSView { controller.view }
    #else
    let controller: UIHostingController<Content>
    private let window: UIWindow
    #endif
    private(set) var size: CGSize

    init(_ content: Content, width: CGFloat, height: CGFloat?, scheme: ColorScheme, compact: Bool) {
        size = CGSize(width: width, height: height ?? 4000)
        #if os(macOS)
        controller = NSHostingController(rootView: content)
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentViewController = controller
        #else
        controller = UIHostingController(rootView: content)
        controller.traitOverrides.horizontalSizeClass = compact ? .compact : .regular
        // No status bar or home indicator: the same for every device size (an iPad rendered on the iPhone Simulator
        // would otherwise get the iPhone's), and the window's safe area had moved some captures and not others.
        controller.safeAreaRegions = []
        let scene = UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as! UIWindowScene
        window = UIWindow(windowScene: scene)
        window.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        window.rootViewController = controller
        window.isHidden = false
        #endif
        resize()
        settle()
        if height == nil {
            size.height = ceil(controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
            resize()
            settle()
        }
    }

    private func resize() {
        #if os(macOS)
        window.setContentSize(size)
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.layoutSubtreeIfNeeded()
        #else
        window.frame = CGRect(origin: .zero, size: size)
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        #endif
    }

    #if os(iOS)
    /// The window as on screen, at 1× (a quarter of 2×'s size in the repo; layout, spacing and colour changes still
    /// show). Drawn from the render server, so 3D transforms (Cover Flow) come out too.
    /// Taken once two frames in a row come out the same (for up to 2 seconds): a fixed wait caught a test's first
    /// screen with its backdrop and glass still fading in, so it never matched again.
    func image() -> UIImage {
        var last = render()
        for _ in 0..<20 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            let next = render()
            if next.pngData() == last.pngData() { return next }
            last = next
        }
        return last
    }

    /// 8-bit sRGB and round-tripped through PNG, so it's compared exactly as a reference is stored: the renderer's
    /// default wide-colour image compared against the saved PNG failed on soft edges (a glass bar's shadow) that
    /// were identical once saved.
    private func render() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
        return UIImage(data: image.pngData()!, scale: 1)!
    }
    #endif

    /// Lets layout passes, `onGeometryChange` and tasks run.
    private func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3)) }

    func close() {
        #if os(macOS)
        window.contentViewController = nil
        #else
        window.isHidden = true
        window.rootViewController = nil
        #endif
    }
}
