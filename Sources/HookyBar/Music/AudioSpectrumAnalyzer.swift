import Accelerate
import Foundation

/// FFT с окном Hann и логарифмическими частотными полосами.
final class AudioSpectrumAnalyzer {
    private let count = 2048
    private let sampleRate: Double
    private let fft = vDSP_create_fftsetup(11, FFTRadix(kFFTRadix2))!
    private var real = [Float](repeating: 0, count: 2048)
    private var imaginary = [Float](repeating: 0, count: 2048)
    private var samples = [Float](repeating: 0, count: 2048)
    private var window = [Float](repeating: 0, count: 2048)
    private var cursor = 0
    private var envelope = [CGFloat](repeating: 0, count: 12)
    private let publish: ([CGFloat], CGFloat) -> Void

    init(sampleRate: Double, publish: @escaping ([CGFloat], CGFloat) -> Void = {
        AudioSpectrumSignal.shared.update(bands: $0, level: $1)
    }) {
        self.sampleRate = sampleRate
        self.publish = publish
        vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
    }

    func append(_ sample: Float) {
        appendBuffered(sample)
    }

    /// Принимает целый CoreAudio-буфер одним вызовом и выбирает самый сильный
    /// канал каждого кадра. Спектр остаётся стереосовместимым даже при противофазе,
    /// но FFT выполняется один раз
    /// вместо отдельного анализа левого и правого каналов.
    func appendInterleaved(
        _ input: UnsafePointer<Float>,
        frameCount: Int,
        channelCount: Int
    ) {
        guard frameCount > 0, channelCount > 0 else { return }
        let mixedChannels = min(channelCount, 2)
        for frame in 0..<frameCount {
            let offset = frame * channelCount
            var mixed = input[offset]
            for channel in 1..<mixedChannels {
                let candidate = input[offset + channel]
                if abs(candidate) > abs(mixed) { mixed = candidate }
            }
            appendBuffered(mixed)
        }
    }

    @inline(__always)
    private func appendBuffered(_ sample: Float) {
        samples[cursor] = sample.isFinite ? sample : 0
        cursor += 1
        guard cursor == count else { return }
        cursor = 0
        vDSP_vmul(samples, 1, window, 1, &real, 1, vDSP_Length(count))
        imaginary.withUnsafeMutableBufferPointer { $0.initialize(repeating: 0) }
        real.withUnsafeMutableBufferPointer { r in
            imaginary.withUnsafeMutableBufferPointer { i in
                var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                vDSP_fft_zip(fft, &split, 1, 11, FFTDirection(FFT_FORWARD))
            }
        }
        for band in 0..<12 {
            let low = 40 * pow(400, Double(band) / 12)
            let high = 40 * pow(400, Double(band + 1) / 12)
            let start = min(count / 2 - 1, max(1, Int(low * Double(count) / sampleRate)))
            let end = min(count / 2, max(start + 1, Int(high * Double(count) / sampleRate)))
            var peak: Float = 0
            for bin in start..<end {
                peak = max(peak, hypot(real[bin], imaginary[bin]) * 4 / Float(count))
            }
            let db = 20 * log10(max(peak, 0.000001))
            let target = CGFloat(min(1, max(0, (db + 65) / 60)))
            let seconds = Double(count) / sampleRate
            let smoothing = CGFloat(1 - exp(-seconds / (target > envelope[band] ? 0.035 : 0.22)))
            envelope[band] += (target - envelope[band]) * smoothing
        }
        publish(envelope, envelope.max() ?? 0)
    }

    deinit { vDSP_destroy_fftsetup(fft) }
}
