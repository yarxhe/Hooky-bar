import SwiftUI

/// Общий спектр реального системного аудио для обоих размеров плеера.
struct SpectrumView: View {
    let signal: AudioSpectrumSignal
    var colors: [Color] = [.indigo]
    let active: Bool
    var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active || reduceMotion)) { timeline in
            // Read outside the drawing closure: each timeline tick supplies fresh value data.
            let spectrum = signal.snapshot(at: timeline.date).bands
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                let count = expanded ? 12 : 9
                let width: CGFloat = expanded ? 3 : 2.5
                let spacing: CGFloat = expanded ? 4 : 2
                let totalWidth = CGFloat(count) * width + CGFloat(count - 1) * spacing
                let startX = (size.width - totalWidth) / 2
                var path = Path()
                for index in 0..<count {
                    let band = min(spectrum.count - 1, index * spectrum.count / count)
                    let level: CGFloat = active && !reduceMotion && band >= 0 ? spectrum[band] : 0
                    let height = 3 + level * max(0, size.height - 3)
                    let rect = CGRect(x: startX + CGFloat(index) * (width + spacing),
                                      y: (size.height - height) / 2, width: width, height: height)
                    path.addRoundedRect(in: rect, cornerSize: CGSize(width: width / 2, height: width / 2))
                }
                context.fill(path, with: .color(.white.opacity(active ? 0.85 : 0.3)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CompactSpectrumView: View {
    let signal: AudioSpectrumSignal
    var colors: [Color] = [.indigo]
    let active: Bool
    var body: some View {
        SpectrumView(signal: signal, colors: colors, active: active, expanded: false)
    }
}
