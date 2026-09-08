import Foundation
import Testing
@testable import HookyBar

struct AudioSpectrumAnalyzerTests {
    @Test func renderFramesReadNewSamplesAndDecayStaleAudio() {
        let signal = AudioSpectrumSignal()
        signal.update(bands: [0.2, 0.8], level: 0.8)
        #expect(signal.snapshot().bands == [0.2, 0.8])
        signal.update(bands: [0.9, 0.1], level: 0.9)
        #expect(signal.snapshot().bands == [0.9, 0.1])
        let stale = signal.snapshot(at: Date().addingTimeInterval(2))
        #expect(stale.bands.allSatisfy { $0 < 0.001 })
    }

    @Test func silenceAndInvalidSamplesRemainSilent() {
        var result: [CGFloat] = []
        let analyzer = AudioSpectrumAnalyzer(sampleRate: 48000) { result = $0; _ = $1 }
        for index in 0..<8192 { analyzer.append(index.isMultiple(of: 2) ? 0 : .nan) }
        #expect(result.count == 12)
        #expect(result.allSatisfy { $0 == 0 })
    }

    @Test func frequencyMovesPeakAndSilenceDecays() {
        func peak(at frequency: Double) -> Int {
            var result: [CGFloat] = []
            let analyzer = AudioSpectrumAnalyzer(sampleRate: 48000) { result = $0; _ = $1 }
            for index in 0..<16384 {
                analyzer.append(Float(sin(2 * .pi * frequency * Double(index) / 48000) * 0.2))
            }
            #expect(result.allSatisfy { $0.isFinite && (0...1).contains($0) })
            let peak = result.indices.max(by: { result[$0] < result[$1] })!
            #expect(result[peak] > 0.5)
            for _ in 0..<96000 { analyzer.append(0) }
            #expect(result.allSatisfy { $0 < 0.01 })
            return peak
        }
        #expect(peak(at: 100) < peak(at: 4000))
    }

    @Test func interleavedStereoUsesOneCombinedSpectrum() {
        var result: [CGFloat] = []
        let analyzer = AudioSpectrumAnalyzer(sampleRate: 48_000) { result = $0; _ = $1 }
        var stereo = [Float]()
        stereo.reserveCapacity(4_096)
        for frame in 0..<2_048 {
            let sample = Float(sin(2 * .pi * 440 * Double(frame) / 48_000) * 0.25)
            stereo.append(sample)
            stereo.append(sample)
        }
        stereo.withUnsafeBufferPointer {
            analyzer.appendInterleaved($0.baseAddress!, frameCount: 2_048, channelCount: 2)
        }
        #expect(result.count == 12)
        #expect((result.max() ?? 0) > 0.5)
    }
}
