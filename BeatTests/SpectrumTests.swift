import XCTest
@testable import Beat

final class SpectrumTests: XCTestCase {
    private let rate = 44_100.0

    private func sine(_ hz: Double, amplitude: Float = 0.8) -> [Float] {
        (0..<SpectrumAnalyzer.size).map { amplitude * Float(sin(2 * .pi * hz * Double($0) / rate)) }
    }

    private func band(containing hz: Float) -> Int {
        SpectrumAnalyzer.edges.indices.dropLast().first { SpectrumAnalyzer.edges[$0] <= hz && hz < SpectrumAnalyzer.edges[$0 + 1] }!
    }

    func testToneLandsInItsBand() {
        let frame = SpectrumAnalyzer().analyze(sine(1000), sampleRate: rate)
        let peak = frame.bands.indices.max { frame.bands[$0] < frame.bands[$1] }!
        XCTAssertLessThanOrEqual(abs(peak - band(containing: 1000)), 1, "peak band \(peak)")
        XCTAssertGreaterThan(frame.level, 0.5)
    }

    func testSilenceIsZero() {
        let frame = SpectrumAnalyzer().analyze([Float](repeating: 0, count: SpectrumAnalyzer.size), sampleRate: rate)
        XCTAssertEqual(frame.bands.max(), 0)
        XCTAssertEqual(frame.level, 0)
        XCTAssertEqual(frame.bass, 0)
    }

    func testLowToneRaisesBassNotHighs() {
        let frame = SpectrumAnalyzer().analyze(sine(60), sampleRate: rate)
        XCTAssertGreaterThan(frame.bass, 0.5)
        let highs = frame.bands[band(containing: 4000)...]
        XCTAssertLessThan(highs.max() ?? 1, 0.3)
    }

    func testBandsAreLogSpacedAndCoverTheRange() {
        let edges = SpectrumAnalyzer.edges
        XCTAssertEqual(edges.count, SpectrumAnalyzer.bandCount + 1)
        XCTAssertEqual(edges.first!, SpectrumAnalyzer.lowHz, accuracy: 0.01)
        XCTAssertEqual(edges.last!, SpectrumAnalyzer.highHz, accuracy: 1)
        let ratios = zip(edges.dropFirst(), edges).map { $0 / $1 }
        XCTAssertEqual(ratios.max()!, ratios.min()!, accuracy: 0.001, "constant ratio = log spacing")
    }

    func testEveryBandGetsAValueEvenWhenNarrowerThanABin() {
        let bins = (0..<(SpectrumAnalyzer.size / 2)).map { Float($0) / Float(SpectrumAnalyzer.size / 2) }
        let bands = SpectrumAnalyzer.bands(from: bins, binHz: Float(rate) / Float(SpectrumAnalyzer.size))
        XCTAssertEqual(bands.count, SpectrumAnalyzer.bandCount)
        XCTAssertTrue(bands.allSatisfy { $0 >= 0 })
        XCTAssertEqual(bands, bands.sorted(), "rising bins give rising bands")
    }

    func testSmootherRisesFastFallsSlowAndStaysInRange() {
        var smoother = Smoother(count: 1)
        let up = smoother.update([1])[0]
        XCTAssertGreaterThan(up, 0.5)
        let down = smoother.update([0])[0]
        XCTAssertGreaterThan(down, up * 0.8, "falls slowly")
        for _ in 0..<200 { _ = smoother.update([2]) }
        XCTAssertLessThanOrEqual(smoother.values[0], 1)
        for _ in 0..<200 { _ = smoother.update([-1]) }
        XCTAssertGreaterThanOrEqual(smoother.values[0], 0)
    }

    func testDownsampleKeepsPeakAndSign() {
        var samples = [Float](repeating: 0.1, count: 2048)
        samples[100] = -0.9
        let points = SpectrumAnalyzer.downsample(samples, to: 256)
        XCTAssertEqual(points.count, 256)
        XCTAssertEqual(points.min(), -0.9)
    }

    func testRingBufferReturnsLatestInOrder() {
        let buffer = SampleBuffer()
        let total = SampleBuffer.capacity + 10
        buffer.write((0..<total).map(Float.init))
        let latest = buffer.latest().samples
        XCTAssertEqual(latest.count, SampleBuffer.capacity)
        XCTAssertEqual(latest.first, Float(total - SampleBuffer.capacity))
        XCTAssertEqual(latest.last, Float(total - 1))
    }

    // MARK: Cover bounce (Radial)

    func testCoverRestsAtFullSizeInSilence() {
        var bounce = CoverBounce()
        for _ in 0..<120 { _ = bounce.update(bass: 0, dt: 1 / 60) }
        XCTAssertEqual(bounce.scale, 1, accuracy: 0.001)
    }

    func testKickPushesCoverOutThenItOvershootsBack() {
        var bounce = CoverBounce()
        for _ in 0..<30 { _ = bounce.update(bass: 0, dt: 1 / 60) }
        // One kick: the bass jumps, then falls away.
        var scales: [Double] = []
        for step in 0..<60 { scales.append(bounce.update(bass: step < 3 ? 0.8 : 0, dt: 1 / 60)) }
        let peak = scales.max()!
        XCTAssertGreaterThan(peak, 1.04, "a kick should visibly push the cover out")
        let afterPeak = scales[scales.firstIndex(of: peak)!...]
        XCTAssertLessThan(afterPeak.min()!, 1, "the spring should swing back past full size: that's the bounce")
        XCTAssertEqual(scales.last!, 1, accuracy: 0.01, "and settle within a second")
    }

    func testCoverScaleStaysWithinLimits() {
        var bounce = CoverBounce()
        for step in 0..<600 {
            let scale = bounce.update(bass: step % 2 == 0 ? 1 : 0, dt: 0.05)
            XCTAssertGreaterThanOrEqual(scale, 0.88)
            XCTAssertLessThanOrEqual(scale, 1.23)
        }
    }

    func testRadialBarsFadeOutTowardsTheTitleBelow() {
        XCTAssertEqual(RadialBars.visibility(pointing: CGPoint(x: 0, y: -1)), 1, "above")
        XCTAssertEqual(RadialBars.visibility(pointing: CGPoint(x: 1, y: 0)), 1, "to the side")
        XCTAssertEqual(RadialBars.visibility(pointing: CGPoint(x: 0, y: 1)), 0, "straight down, over the title")
        let diagonal = RadialBars.visibility(pointing: CGPoint(x: 0.707, y: 0.707))
        XCTAssertLessThan(diagonal, 0.1, "already mostly gone halfway down")
    }
}
