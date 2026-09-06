import SwiftUI

/// Цветное поле и широкие световые потоки рисуются в размере панели.
/// Никаких уменьшенных растровых текстур: края остаются гладкими на Retina.
struct LiquidEtherBackground: View {
    let colors: [Color]
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let palette = BackgroundPalette(colors: colors)
        LiquidEtherField(colorVector: palette, active: active)
            .animation(reduceMotion ? nil : HookyMotion.backgroundPalette, value: palette)
    }
}

private struct LiquidEtherField: View, Animatable {
    var colorVector: BackgroundPalette
    let active: Bool

    var animatableData: BackgroundPalette {
        get { colorVector }
        set { colorVector = newValue }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black
            // Mesh остаётся вне TimelineView: меняется только при смене палитры.
            // Это избавляет CPU от перестройки 16 цветовых ячеек каждый кадр.
            colorField(at: 0)
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active || reduceMotion)) { timeline in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                flowingLight(at: time)
            }
        }
        .overlay {
            LinearGradient(
                colors: [.black.opacity(0.42), .black.opacity(0.08), .black.opacity(0.4)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // Цвета уже интерполированы animatableData. Mesh не должен запускать
        // собственную анимацию заново для каждого промежуточного кадра.
        .transaction { $0.animation = nil }
    }

    @ViewBuilder
    private func colorField(at time: TimeInterval) -> some View {
        if #available(macOS 15.0, *) {
            MeshGradient(
                width: 5, height: 5,
                points: meshPoints(at: time),
                colors: meshColors,
                background: .black,
                smoothsColors: true
            )
            .blur(radius: 12)
            .scaleEffect(1.12)
        } else {
            LinearGradient(
                colors: [palette[0].opacity(0.6), palette[1].opacity(0.4), palette[2].opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func flowingLight(at time: TimeInterval) -> some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            context.addFilter(.blur(radius: 22))
            context.blendMode = .screen
            for layer in 0..<2 {
                let phase = Double(layer) * 2.8
                let path = lightRibbon(in: size, time: time, phase: phase)
                let gradient = Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: palette[layer].opacity(0.55), location: 0.28),
                    .init(color: palette[(layer + 1) % 3].opacity(0.85), location: 0.6),
                    .init(color: .clear, location: 1)
                ])
                context.fill(path, with: .linearGradient(
                    gradient,
                    startPoint: CGPoint(x: -size.width * 0.15, y: 0),
                    endPoint: CGPoint(x: size.width * 1.15, y: size.height)
                ))
            }
        }
    }

    /// Соседние узлы остаются в своих ячейках: mesh не складывается
    /// и не создаёт острых швов при смене направления движения.
    private func meshPoints(at time: TimeInterval) -> [SIMD2<Float>] {
        (0..<25).map { index in
            let column = index % 5
            let row = index / 5
            let x = Double(column) / 4
            let y = Double(row) / 4
            let dx = column == 0 || column == 4 ? 0 : sin(time * 0.72 + y * 5.2) * 0.075
            let dy = row == 0 || row == 4 ? 0 : cos(time * 0.58 + x * 4.6) * 0.075
            return SIMD2(Float(x + dx), Float(y + dy))
        }
    }

    private var meshColors: [Color] {
        let p = palette
        return [
            .black, p[0].opacity(0.3), p[1].opacity(0.48), p[2].opacity(0.22), .black,
            p[2].opacity(0.25), p[0].opacity(0.78), p[1].opacity(0.5), p[0].opacity(0.16), p[1].opacity(0.3),
            p[0].opacity(0.35), p[2].opacity(0.4), p[0].opacity(0.2), p[1].opacity(0.85), p[2].opacity(0.4),
            p[1].opacity(0.2), p[0].opacity(0.16), p[2].opacity(0.72), p[0].opacity(0.48), p[1].opacity(0.24),
            .black, p[2].opacity(0.28), p[1].opacity(0.4), p[0].opacity(0.24), .black
        ]
    }

    private var palette: [Color] {
        colorVector.colors
    }

    private func lightRibbon(in size: CGSize, time: TimeInterval, phase: Double) -> Path {
        var upper: [CGPoint] = []
        var lower: [CGPoint] = []
        for index in 0...32 {
            let x = Double(index) / 32 * 1.4 - 0.2
            let wave = sin(x * 4.8 + time * 0.84 + phase) * 0.15
                + cos(x * 2.4 - time * 0.52 + phase) * 0.09
            let center = 0.5 + wave + sin(time * 0.4 + phase) * 0.12
            let halfWidth = 0.065 + (sin(x * 3.2 + time * 0.6 + phase) + 1) * 0.035
            upper.append(CGPoint(x: x * size.width, y: (center - halfWidth) * size.height))
            lower.append(CGPoint(x: x * size.width, y: (center + halfWidth) * size.height))
        }
        var path = Path()
        path.addLines(upper + lower.reversed())
        path.closeSubpath()
        return path
    }
}
