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
            // Mesh меняется только при смене палитры; движение слоёв ведёт Core Animation.
            // Это избавляет CPU от перестройки 16 цветовых ячеек каждый кадр.
            colorField(at: 0)
            NativeLightRibbons(palette: colorVector, active: active, reduceMotion: reduceMotion)
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
            // MeshGradient уже интерполирует поле без швов. Дополнительный
            // полноэкранный blur создавал несколько Retina-буферов по 4–5 МБ.
            .scaleEffect(1.04)
        } else {
            LinearGradient(
                colors: [palette[0].opacity(0.6), palette[1].opacity(0.4), palette[2].opacity(0.2)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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

}
