import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Beat

/// A library source for tests: hands out its results one read at a time (the last one repeats), serves art from a
/// dictionary, and counts what it was asked. `holdNextRead` pauses the next read until `release()`, to look at a
/// store while a read is under way.
actor FakeLibrarySource: LibrarySource {
    private var results: [Result<LibrarySnapshot, any Error>]
    private var art: [ArtworkSource: Data]
    private(set) var reads = 0
    private(set) var artRequests: [ArtworkSource] = []
    private var holdNextRead = false
    private var held: CheckedContinuation<Void, Never>?

    init(_ results: [Result<LibrarySnapshot, any Error>] = [], art: [ArtworkSource: Data] = [:]) {
        self.results = results
        self.art = art
    }

    init(tracks: [Track]) { self.init([.success(.build(tracks: tracks))]) }

    func holdNext() { holdNextRead = true }

    func release() {
        held?.resume()
        held = nil
    }

    var isHolding: Bool { held != nil }

    func load() async throws -> LibrarySnapshot {
        reads += 1
        if holdNextRead {
            holdNextRead = false
            await withCheckedContinuation { held = $0 }
        }
        let result = results.count > 1 ? results.removeFirst() : results.first ?? .success(.empty)
        return try result.get()
    }

    func artworkData(for source: ArtworkSource) async -> Data? {
        artRequests.append(source)
        return art[source]
    }
}

/// A player for `PlaybackQueue` tests: plays nothing, records each call. Tests play its part by calling `onTime`,
/// `onAdvanced` and `onFinished` themselves.
@MainActor
final class FakePlayer: AudioPlaying {
    enum Call: Equatable {
        case load(URL, upcoming: URL?, autoplay: Bool)
        case upcoming(URL?)
        case play, pause, stop
        case seek(TimeInterval)
    }

    private(set) var calls: [Call] = []
    var onTime: ((TimeInterval) -> Void)?
    var onAdvanced: (() -> Void)?
    var onFinished: (() -> Void)?
    var volume: Float = 1
    let outputPlayer = AVPlayer()
    let samples = SampleBuffer()

    func load(_ url: URL, upcoming: URL?, autoplay: Bool) { calls.append(.load(url, upcoming: upcoming, autoplay: autoplay)) }
    func setUpcoming(_ url: URL?) { calls.append(.upcoming(url)) }
    func play() { calls.append(.play) }
    func pause() { calls.append(.pause) }
    func seek(to seconds: TimeInterval) { calls.append(.seek(seconds)) }
    func stop() { calls.append(.stop) }

    func clear() { calls = [] }
}

struct TestError: Error {}

/// Images drawn with Core Graphics, so tests run the same on the Mac and on iOS.
enum TestImages {
    static func image(width: Int = 8, red: CGFloat = 1) -> CGImage {
        let context = CGContext(data: nil, width: width, height: width, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: red, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: width))
        return context.makeImage()!
    }

    static func png(width: Int = 8, red: CGFloat = 1) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image(width: width, red: red), nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}

extension XCTestCase {
    /// A fresh folder under the temporary directory, removed when the test ends.
    func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BeatTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder
    }

    /// Defaults of its own, so tests never read or change Beat's; removed when the test ends.
    func temporaryDefaults() -> UserDefaults {
        let name = "BeatTests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }

    /// Waits until `condition` holds, for state that settles on other tasks; fails after `timeout`.
    @MainActor
    func eventually(timeout: Duration = .seconds(2), _ message: String = "condition never held",
                    _ condition: @MainActor () async -> Bool) async {
        let clock = ContinuousClock(), deadline = clock.now + timeout
        while clock.now < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail(message)
    }
}
