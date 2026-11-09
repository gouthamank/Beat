import Accelerate

/// One analysed moment of audio, all values 0…1.
struct SpectrumFrame: Equatable, Sendable {
    var bands: [Float]
    /// RMS loudness.
    var level: Float
    /// Average of the bands below 150 Hz.
    var bass: Float
    /// Samples (-1…1) for the oscilloscope.
    var waveform: [Float]

    static let silent = SpectrumFrame(
        bands: Array(repeating: 0, count: SpectrumAnalyzer.bandCount), level: 0, bass: 0,
        waveform: Array(repeating: 0, count: SpectrumAnalyzer.waveformPoints)
    )
}

/// Turns the latest samples into frequency bands. Owns its FFT setup and scratch space; used on the
/// main thread at display rate, never on the audio thread.
final class SpectrumAnalyzer {
    static let size = SampleBuffer.capacity
    static let bandCount = 64
    static let waveformPoints = 256
    static let lowHz: Float = 30
    static let highHz: Float = 16_000
    static let bassHz: Float = 150
    /// Decibel range mapped to 0…1.
    static let floorDB: Float = -80
    static let ceilingDB: Float = -12

    private let fft: vDSP.FFT<DSPSplitComplex>?
    private let window: [Float]
    private var real = [Float](repeating: 0, count: SpectrumAnalyzer.size / 2)
    private var imag = [Float](repeating: 0, count: SpectrumAnalyzer.size / 2)

    init() {
        fft = vDSP.FFT(log2n: vDSP_Length(log2(Float(Self.size))), radix: .radix2, ofType: DSPSplitComplex.self)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: Self.size, isHalfWindow: false)
    }

    /// Band edges in Hz: `bandCount + 1` log-spaced values from `lowHz` to `highHz`.
    static let edges: [Float] = (0...bandCount).map { k in
        lowHz * pow(highHz / lowHz, Float(k) / Float(bandCount))
    }

    func analyze(_ samples: [Float], sampleRate: Double) -> SpectrumFrame {
        let n = Self.size
        guard samples.count == n, let fft else { return .silent }
        let half = n / 2

        // Window, FFT, magnitudes.
        let windowed = vDSP.multiply(samples, window)
        var magnitudes = [Float](repeating: 0, count: half)
        real.withUnsafeMutableBufferPointer { rp in
            imag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { wp in
                    wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { complex in
                        vDSP_ctoz(complex, 2, &split, 1, vDSP_Length(half))
                    }
                }
                let input = split
                fft.forward(input: input, output: &split)   // in place: same buffers
                magnitudes.withUnsafeMutableBufferPointer { mp in
                    vDSP_zvabs(&split, 1, mp.baseAddress!, 1, vDSP_Length(half))
                }
            }
        }
        // Dividing by n puts a loud, full-scale tone around -6 dB, which the 0…1 range treats as full.
        let scale = 1 / Float(n)
        let normalized = magnitudes.map { normalize(decibels: 20 * log10($0 * scale + 1e-9)) }

        let binHz = Float(sampleRate) / Float(n)
        let bands = Self.bands(from: normalized, binHz: binHz)
        let bassBands = zip(bands, Self.edges).filter { $0.1 < Self.bassHz }.map(\.0)
        let bass = bassBands.isEmpty ? 0 : bassBands.reduce(0, +) / Float(bassBands.count)

        let rms = vDSP.rootMeanSquare(samples)
        let level = normalize(decibels: 20 * log10(rms + 1e-9), floor: -50, ceiling: 0)

        return SpectrumFrame(bands: bands, level: level, bass: bass, waveform: Self.downsample(samples, to: Self.waveformPoints))
    }

    /// Each band takes its loudest bin; a band narrower than one bin uses the bin at its centre.
    static func bands(from bins: [Float], binHz: Float) -> [Float] {
        (0..<bandCount).map { k in
            let low = edges[k], high = edges[k + 1]
            let first = Int((low / binHz).rounded(.up)), last = Int((high / binHz).rounded(.down))
            let lo = max(first, 0), hi = min(last, bins.count - 1)
            if lo <= hi { return bins[lo...hi].max() ?? 0 }
            let centre = Int((sqrt(low * high) / binHz).rounded()).clamped(to: 0...(bins.count - 1))
            return bins[centre]
        }
    }

    /// Keeps the largest-magnitude sample from each chunk, so peaks and their sign survive.
    static func downsample(_ samples: [Float], to points: Int) -> [Float] {
        guard !samples.isEmpty, points > 0 else { return [] }
        let chunk = max(samples.count / points, 1)
        return (0..<points).map { p in
            let start = min(p * chunk, samples.count - 1)
            let end = min(start + chunk, samples.count)
            return samples[start..<end].max { abs($0) < abs($1) } ?? 0
        }
    }

    private func normalize(decibels: Float, floor: Float = SpectrumAnalyzer.floorDB, ceiling: Float = SpectrumAnalyzer.ceilingDB) -> Float {
        ((decibels - floor) / (ceiling - floor)).clamped(to: 0...1)
    }
}

/// Eases values towards their targets: fast up, slow down, so motion is lively but not twitchy.
struct Smoother {
    var rise: Float = 0.6
    var fall: Float = 0.12
    private(set) var values: [Float]

    init(count: Int) { values = Array(repeating: 0, count: count) }

    mutating func update(_ targets: [Float]) -> [Float] {
        if values.count != targets.count { values = Array(repeating: 0, count: targets.count) }
        for i in values.indices {
            let delta = targets[i] - values[i]
            values[i] = (values[i] + delta * (delta > 0 ? rise : fall)).clamped(to: 0...1)
        }
        return values
    }
}
