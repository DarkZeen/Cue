import Accelerate
import AudioToolbox
import Foundation
import os

/// Turns a stream of samples into nine numbers, on the thread the samples
/// arrive on.
///
/// Everything here runs inside a Core Audio IO callback, which is a real-time
/// thread: it must not allocate, must not wait on a lock anything slow holds,
/// and must not touch anything of SwiftUI's. So the buffers are allocated once
/// up front, the FFT is `vDSP`'s, and the only shared state is one small struct
/// behind an unfair lock that the main thread reads sixty times a second and
/// this writes to at the end of each callback.
/// `nonisolated` explicitly, and it is not decoration. The package compiles
/// with main-actor isolation by default, which quietly makes an unannotated
/// class — and any closure written inside it — main-actor bound. A Core Audio
/// IO callback runs on a real-time thread, so the first thing that closure did
/// was assert it was on the main queue, and the app trapped the instant music
/// started.
nonisolated final class SpectrumAnalyser: @unchecked Sendable {
    struct Reading: Sendable {
        var level: Double = 0
        var bands: [Double] = []
    }

    /// How many bands the mark is drawn from. Nine, matching what the bars
    /// have always drawn: seventeen mirrored strokes from nine readings.
    ///
    /// Lives here rather than on `AudioTap` because that class is main-actor
    /// isolated, and a constant on it cannot be read from the audio thread —
    /// not even a `let`.
    static let bandCount = 9

    private let snapshot = OSAllocatedUnfairLock(initialState: Reading())

    /// 1024 samples: about 21ms at 48kHz, which is short enough to follow a
    /// beat and long enough that the low bands have something to resolve. A
    /// shorter window cannot see bass at all — 512 samples at this rate puts
    /// the first bin at 94Hz, which is most of a kick drum.
    private static let windowSize = 1024
    private static let log2n = vDSP_Length(10)

    private nonisolated(unsafe) var fft: FFTSetup?
    private var window = [Float](repeating: 0, count: windowSize)
    private var ring = [Float](repeating: 0, count: windowSize)
    private var ringFill = 0

    private var real = [Float](repeating: 0, count: windowSize / 2)
    private var imaginary = [Float](repeating: 0, count: windowSize / 2)
    private var magnitudes = [Float](repeating: 0, count: windowSize / 2)
    private var scratch = [Float](repeating: 0, count: windowSize)

    private var sampleRate: Double = 48_000
    private var channels = 2

    /// Where each band ends, as a bin index. Computed once, because doing it
    /// per callback is a logarithm per band per 21ms for a number that never
    /// changes.
    private var bandEdges: [Int] = []

    /// The envelope's memory. Fast up, slow down — the shape a meter needs to
    /// catch a transient and then let it fall, rather than flickering at the
    /// rate the samples arrive.
    private var smoothed = [Double](repeating: 0, count: SpectrumAnalyser.bandCount)
    private var smoothedLevel: Double = 0

    init() {
        fft = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))
        vDSP_hann_window(&window, vDSP_Length(Self.windowSize), Int32(vDSP_HANN_NORM))
    }

    deinit {
        if let fft { vDSP_destroy_fftsetup(fft) }
    }

    func prepare(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate > 0 ? sampleRate : 48_000
        self.channels = max(channels, 1)
        bandEdges = Self.edges(sampleRate: self.sampleRate, bins: Self.windowSize / 2)
    }

    func reset() {
        ringFill = 0
        smoothed = [Double](repeating: 0, count: Self.bandCount)
        smoothedLevel = 0
        snapshot.withLock { $0 = Reading() }
    }

    func latest() -> Reading {
        snapshot.withLock { $0 }
    }

    // MARK: - The callback

    func consume(_ input: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, let data = first.mData else { return }

        let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        guard frames > 0 else { return }

        let samples = data.bindMemory(to: Float.self, capacity: frames)

        // One channel is enough. A stereo mixdown costs an add and a multiply
        // per sample for a spectrum that is, on almost all music, the same
        // shape — and this runs on a thread with a deadline.
        var index = 0
        while index < frames {
            let take = min(Self.windowSize - ringFill, frames - index)
            for offset in 0..<take {
                ring[ringFill + offset] = samples[index + offset]
            }
            ringFill += take
            index += take

            if ringFill == Self.windowSize {
                analyse()
                ringFill = 0
            }
        }
    }

    private func analyse() {
        guard let fft, !bandEdges.isEmpty else { return }

        vDSP_vmul(ring, 1, window, 1, &scratch, 1, vDSP_Length(Self.windowSize))

        real.withUnsafeMutableBufferPointer { realPointer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryPointer in
                var split = DSPSplitComplex(
                    realp: realPointer.baseAddress!,
                    imagp: imaginaryPointer.baseAddress!
                )

                scratch.withUnsafeBufferPointer { source in
                    source.baseAddress!.withMemoryRebound(
                        to: DSPComplex.self,
                        capacity: Self.windowSize / 2
                    ) { reinterpreted in
                        vDSP_ctoz(reinterpreted, 2, &split, 1, vDSP_Length(Self.windowSize / 2))
                    }
                }

                vDSP_fft_zrip(fft, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(Self.windowSize / 2))

                // `vDSP_fft_zrip` returns magnitudes scaled by the transform
                // length, which puts a full-scale signal in the thousands. The
                // decibel conversion below only means anything against a
                // signal that peaks near one.
                var scale = Float(1.0 / Double(Self.windowSize))
                magnitudes.withUnsafeMutableBufferPointer { bins in
                    vDSP_vsmul(
                        bins.baseAddress!, 1, &scale, bins.baseAddress!, 1,
                        vDSP_Length(Self.windowSize / 2)
                    )
                }
            }
        }

        var reading = Reading()
        reading.bands = [Double](repeating: 0, count: Self.bandCount)

        for band in 0..<Self.bandCount {
            let start = band == 0 ? 1 : bandEdges[band - 1]
            let end = max(bandEdges[band], start + 1)

            var sum: Float = 0
            for bin in start..<min(end, magnitudes.count) { sum += magnitudes[bin] }
            let mean = Double(sum) / Double(max(end - start, 1))

            // Decibels, not amplitude. Loudness is logarithmic and a linear
            // meter spends its life near zero with occasional spikes — which
            // is precisely the "flat with the odd twitch" look that reads as
            // broken rather than as quiet.
            let decibels = 20 * log10(max(mean, 1e-7))
            let normalised = (decibels + 72) / 72

            smoothed[band] = Self.envelope(smoothed[band], toward: min(max(normalised, 0), 1))
            reading.bands[band] = smoothed[band]
        }

        // Weighted towards the low end, because that is where a beat lives and
        // the level is what the whole mark pulses on.
        var weightedSum = 0.0
        var weights = 0.0
        for band in 0..<Self.bandCount {
            let weight = 1.0 - 0.6 * (Double(band) / Double(Self.bandCount - 1))
            weightedSum += smoothed[band] * weight
            weights += weight
        }
        smoothedLevel = Self.envelope(smoothedLevel, toward: weightedSum / max(weights, 0.001))
        reading.level = smoothedLevel

        let settled = reading
        snapshot.withLock { $0 = settled }
    }

    /// Fast attack, slow release.
    ///
    /// A symmetric filter is the thing that makes a meter look like it is
    /// lagging the music: it rounds off the front of every hit, which is the
    /// only part the eye actually reads as a beat.
    private static func envelope(_ current: Double, toward target: Double) -> Double {
        target > current
            ? current + (target - current) * 0.55
            : current + (target - current) * 0.14
    }

    /// Nine bands, spaced logarithmically between 40Hz and 14kHz.
    ///
    /// Even spacing would give eight bands of cymbal and one of everything
    /// anybody can hum. Pitch is logarithmic and so are the bands.
    private static func edges(sampleRate: Double, bins: Int) -> [Int] {
        let low = 40.0
        let high = min(14_000.0, sampleRate / 2 - 1)
        let hzPerBin = sampleRate / 2 / Double(bins)

        return (1...Self.bandCount).map { band in
            let fraction = Double(band) / Double(Self.bandCount)
            let frequency = low * pow(high / low, fraction)
            return min(Int(frequency / hzPerBin), bins - 1)
        }
    }
}
