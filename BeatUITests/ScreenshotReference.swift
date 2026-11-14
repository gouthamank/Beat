import AppKit
import XCTest

/// Compares a UI test's screenshot with a reference image, as the unit tests' snapshots do. Written here because
/// swift-snapshot-testing can't be used in a UI-test bundle (Xcode builds those with Swift Testing switched off, and the
/// library imports it).
///
/// The test runner is sandboxed, so it can't touch the repo: references in `BeatUITests/__Snapshots__` are built into
/// the test bundle, which it can read. A missing or different screenshot fails the test and is attached to the results
/// (named `screenshot.<reference>`); `make mac-test-ui-record` saves those attachments as the new references.
enum ScreenshotReference {
    /// Matches when at most this share of pixels differ by more than `tolerance` in any channel (0–255).
    static let allowedDifference = 0.01
    static let tolerance = 6

    @MainActor
    static func assertMatches(_ png: Data, named name: String, file: StaticString = #filePath,
                              testName: String = #function, line: UInt = #line) {
        let testClass = URL(fileURLWithPath: "\(file)").deletingPathExtension().lastPathComponent
        let reference = "\(testClass).\(testName.replacingOccurrences(of: "()", with: "")).\(name)"
        let old = Bundle(for: BeatUITestCase.self).url(forResource: reference, withExtension: "png")
            .flatMap { try? Data(contentsOf: $0) }

        let problem: String
        if let old {
            let differing = difference(old, png)
            if let differing, differing <= allowedDifference { return }
            problem = differing.map { String(format: "%.1f%% of pixels differ from the reference", $0 * 100) }
                ?? "the size differs from the reference"
            attach(old, named: "reference.\(reference)")
        } else {
            problem = "no reference yet"
        }
        attach(png, named: "screenshot.\(reference)")
        XCTFail("\(reference): \(problem). The screenshot is attached to this test's results; if it's right, save it as "
                + "the reference with make mac-test-ui-record.", file: file, line: line)
    }

    @MainActor
    private static func attach(_ png: Data, named name: String) {
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: name) { $0.add(attachment) }
    }

    /// The share of pixels that differ by more than `tolerance`, or nil when the images can't be compared (sizes).
    static func difference(_ a: Data, _ b: Data) -> Double? {
        guard let x = pixels(a), let y = pixels(b), x.width == y.width, x.height == y.height else { return nil }
        var differing = 0
        for i in stride(from: 0, to: x.bytes.count, by: 4) {
            for c in 0..<4 where abs(Int(x.bytes[i + c]) - Int(y.bytes[i + c])) > tolerance {
                differing += 1
                break
            }
        }
        return Double(differing) / Double(x.width * x.height)
    }

    private static func pixels(_ png: Data) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (bytes, width, height)
    }
}
