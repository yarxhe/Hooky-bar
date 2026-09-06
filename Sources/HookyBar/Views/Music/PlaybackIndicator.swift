import Foundation

enum PlaybackIndicator {
    /// Декоративный индикатор, не FFT: непрерывное движение без случайных скачков.
    static func level(at time: TimeInterval, index: Int, active: Bool, reducedMotion: Bool) -> CGFloat {
        guard active else { return 0 }
        let position = Double(index)
        if reducedMotion { return CGFloat(0.25 + 0.25 * (sin(position * 0.9) + 1) / 2) }
        let primary = (sin(time * 3.2 + position * 0.85) + 1) / 2
        let secondary = (sin(time * 5.1 - position * 1.13) + 1) / 2
        let envelope = 0.65 + 0.35 * (sin(time * 1.4 + position * 0.18) + 1) / 2
        return CGFloat(0.12 + (primary * 0.55 + secondary * 0.3) * envelope)
    }
}
