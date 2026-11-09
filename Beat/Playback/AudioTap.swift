import AVFoundation
import MediaToolbox
import Synchronization

/// The most recent mono samples of what's playing, for the visualizer. Written by the audio tap on the
/// real-time audio thread (a short copy under a lock, no allocation) and read on the main thread.
final class SampleBuffer: Sendable {
    static let capacity = 2048

    private struct Ring {
        var samples = [Float](repeating: 0, count: SampleBuffer.capacity)
        var writeIndex = 0
        var sampleRate: Double = 44_100
        var channels = 2
        var isFloat = true
        var isNonInterleaved = true

        mutating func append(_ value: Float) {
            samples[writeIndex] = value
            writeIndex = (writeIndex + 1) % samples.count
        }
    }

    private let ring = Mutex(Ring())

    /// Called from the tap's prepare callback, before audio flows.
    func setFormat(_ format: AudioStreamBasicDescription) {
        ring.withLock { r in
            r.sampleRate = format.mSampleRate
            r.channels = max(Int(format.mChannelsPerFrame), 1)
            r.isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0 && format.mBitsPerChannel == 32
            r.isNonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        }
    }

    /// Mixes a buffer list to mono and appends it. Runs on the audio thread: no allocation, no logging,
    /// and never waits. If the main thread is mid-copy the buffer is skipped; the visualizer misses a few
    /// milliseconds, but a blocked audio thread would miss its deadline and click.
    func write(_ list: UnsafeMutableAudioBufferListPointer, frames: Int) {
        _ = ring.withLockIfAvailable { r in
            guard r.isFloat, frames > 0, list.count > 0 else { return }
            if r.isNonInterleaved {
                let channels = list.count
                var count = frames
                for b in 0..<channels { count = min(count, Int(list[b].mDataByteSize) / MemoryLayout<Float>.size) }
                for i in 0..<count {
                    var sum: Float = 0
                    for b in 0..<channels {
                        guard let data = list[b].mData else { continue }
                        sum += data.assumingMemoryBound(to: Float.self)[i]
                    }
                    r.append(sum / Float(channels))
                }
            } else {
                guard let data = list[0].mData?.assumingMemoryBound(to: Float.self) else { return }
                let channels = r.channels
                let count = min(frames, Int(list[0].mDataByteSize) / MemoryLayout<Float>.size / channels)
                for i in 0..<count {
                    var sum: Float = 0
                    for c in 0..<channels { sum += data[i * channels + c] }
                    r.append(sum / Float(channels))
                }
            }
        }
    }

    /// Appends already-mono samples. For tests.
    func write(_ values: [Float]) {
        ring.withLock { r in values.forEach { r.append($0) } }
    }

    /// The latest `capacity` samples, oldest first, and their sample rate.
    func latest() -> (samples: [Float], sampleRate: Double) {
        ring.withLock { r in
            let split = r.writeIndex
            return (Array(r.samples[split...] + r.samples[..<split]), r.sampleRate)
        }
    }
}

/// Attaches an `MTAudioProcessingTap` to a player item. The tap passes audio through untouched and
/// copies it into a `SampleBuffer`. The C callbacks reach the buffer through the tap's storage pointer.
enum AudioTap {
    @MainActor
    static func attach(to item: AVPlayerItem, buffer: SampleBuffer) async {
        guard let track = try? await item.asset.loadTracks(withMediaType: .audio).first else { return }

        // Retained for the tap's lifetime; the finalize callback releases it.
        let clientInfo = Unmanaged.passRetained(buffer).toOpaque()
        var callbacks = makeCallbacks(clientInfo: clientInfo)

        var tap: MTAudioProcessingTap?
        guard MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap) == noErr,
              let tap else {
            Unmanaged<SampleBuffer>.fromOpaque(clientInfo).release()
            return
        }

        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        item.audioMix = mix
    }

    /// Built outside the main actor on purpose: closures written inside `attach` would inherit its
    /// main-actor isolation, and Swift's executor check traps when Core Media calls them on its own queues.
    private nonisolated static func makeCallbacks(clientInfo: UnsafeMutableRawPointer) -> MTAudioProcessingTapCallbacks {
        MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: clientInfo,
            init: { _, clientInfo, storageOut in
                storageOut.pointee = clientInfo
            },
            finalize: { tap in
                Unmanaged<SampleBuffer>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
            },
            prepare: { tap, _, format in
                Unmanaged<SampleBuffer>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .setFormat(format.pointee)
            },
            unprepare: nil,
            process: { tap, frames, _, bufferList, framesOut, flagsOut in
                // Fetching the source audio is what lets it continue to the speakers unchanged.
                guard MTAudioProcessingTapGetSourceAudio(tap, frames, bufferList, flagsOut, nil, framesOut) == noErr else { return }
                Unmanaged<SampleBuffer>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
                    .write(UnsafeMutableAudioBufferListPointer(bufferList), frames: Int(framesOut.pointee))
            }
        )
    }
}
