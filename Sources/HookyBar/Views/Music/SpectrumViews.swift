import Cocoa
import SwiftUI

struct SpectrumView: View {
    let signal: AudioSpectrumSignal
    var colors: [Color] = [.yellow]
    let active: Bool
    var expanded = false

    var body: some View {
        TimelineView(.animation(minimumInterval: expanded ? 1.0 / 20.0 : 1.0 / 15.0, paused: !active)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                guard active else { return }
                let snapshot = signal.snapshot()
                let time = timeline.date.timeIntervalSinceReferenceDate
                let allBands = expanded ? Array(snapshot.bands.prefix(12)) : Array(snapshot.bands.dropFirst(1).prefix(9))
                guard !allBands.isEmpty else { return }
                let spacing: CGFloat = expanded ? 4.1 : 2.2
                let barWidth: CGFloat = expanded ? 3.0 : 2.5
                let totalWidth = CGFloat(allBands.count) * barWidth + CGFloat(allBands.count - 1) * spacing
                let startX = (size.width - totalWidth) / 2
                let palette = colors.isEmpty ? [Color.yellow] : colors
                var paths = palette.map { _ in Path() }

                for (index, value) in allBands.enumerated() {
                    let position = Double(index)
                    let tick = time * (8.5 + position.truncatingRemainder(dividingBy: 3) * 0.37)
                    let wholeTick = floor(tick)
                    let progress = tick - wholeTick
                    let smoothProgress = progress * progress * (3 - 2 * progress)
                    let currentRandom = visualizerNoise(wholeTick * 31.7 + position * 97.3)
                    let nextRandom = visualizerNoise((wholeTick + 1) * 31.7 + position * 97.3)
                    let fastRandom = currentRandom + (nextRandom - currentRandom) * smoothProgress
                    let slowTick = time * 1.7
                    let slowWhole = floor(slowTick)
                    let slowProgress = slowTick - slowWhole
                    let slowSmooth = slowProgress * slowProgress * (3 - 2 * slowProgress)
                    let slowStart = visualizerNoise(slowWhole * 13.1 + position * 53.9)
                    let slowEnd = visualizerNoise((slowWhole + 1) * 13.1 + position * 53.9)
                    let slowRandom = slowStart + (slowEnd - slowStart) * slowSmooth
                    let simulated = 0.12 + CGFloat(fastRandom) * 0.70 + CGFloat(slowRandom) * 0.18
                    let captured = max(0, value) * 0.55 + snapshot.level * 0.28
                    let magnitude = min(1, simulated * 0.78 + captured)
                    let height = max(3, 3 + magnitude * max(3, size.height - 4))
                    let rect = CGRect(
                        x: startX + CGFloat(index) * (barWidth + spacing),
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    paths[index % paths.count].addPath(Path(roundedRect: rect, cornerRadius: barWidth / 2))
                }
                for index in paths.indices where !paths[index].isEmpty {
                    context.fill(paths[index], with: .color(palette[index]))
                }
            }
        }
    }

    private func visualizerNoise(_ seed: Double) -> Double {
        let value = sin(seed * 12.9898 + 78.233) * 43_758.5453
        return value - floor(value)
    }
}

struct CompactSpectrumView: View {
    let signal: AudioSpectrumSignal
    var colors: [Color] = [.yellow]
    let active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0, paused: !active)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                guard active else { return }
                let snapshot = signal.snapshot()
                let time = timeline.date.timeIntervalSinceReferenceDate
                let palette = colors.isEmpty ? [Color.yellow] : colors
                let barWidth: CGFloat = 2.5
                let spacing: CGFloat = 2.2
                let count = 9
                let totalWidth = CGFloat(count) * barWidth + CGFloat(count - 1) * spacing
                let startX = (size.width - totalWidth) / 2
                var paths = palette.map { _ in Path() }

                for index in 0..<count {
                    let captured = index + 1 < snapshot.bands.count ? snapshot.bands[index + 1] : 0
                    let wave = (sin(time * (7.2 + Double(index) * 0.31) + Double(index) * 1.47) + 1) / 2
                    let pulse = (sin(time * 2.1 + Double(index) * 0.73) + 1) / 2
                    let magnitude = min(
                        1,
                        CGFloat(wave) * 0.56 + CGFloat(pulse) * 0.24
                            + captured * 0.42 + snapshot.level * 0.2
                    )
                    let height = max(3, 3 + magnitude * max(3, size.height - 4))
                    let rect = CGRect(
                        x: startX + CGFloat(index) * (barWidth + spacing),
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    paths[index % paths.count].addPath(Path(roundedRect: rect, cornerRadius: barWidth / 2))
                }
                for index in paths.indices where !paths[index].isEmpty {
                    context.fill(paths[index], with: .color(palette[index]))
                }
            }
        }
    }
}

struct LiquidEtherBackground: View {
    let colors: [Color]
    let active: Bool

    @ViewBuilder
    var body: some View {
        if #available(macOS 15.0, *) {
            meshBackground
        } else {
            legacyBackground
        }
    }

    @available(macOS 15.0, *)
    private var meshBackground: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let palette = liquidPalette
            let primaryPulse = 0.72 + sin(time * 0.82) * 0.16
            let secondaryPulse = 0.62 + cos(time * 0.68 + 1.3) * 0.18
            MeshGradient(
                width: 4,
                height: 4,
                points: meshPoints(at: time),
                colors: [
                    .black, palette[0].opacity(primaryPulse), palette[1].opacity(secondaryPulse), .black,
                    palette[2].opacity(secondaryPulse), palette[0].opacity(0.94), palette[1].opacity(primaryPulse), palette[2].opacity(0.5),
                    palette[1].opacity(0.48), palette[2].opacity(0.86), palette[0].opacity(secondaryPulse), palette[1].opacity(primaryPulse),
                    .black, palette[2].opacity(primaryPulse), palette[0].opacity(secondaryPulse), .black
                ],
                background: .black,
                smoothsColors: true
            )
            .saturation(1.18)
            .blur(radius: 10)
            .scaleEffect(1.13 + CGFloat(sin(time * 0.57)) * 0.035)
        }
        .overlay {
            LinearGradient(
                colors: [.black.opacity(0.28), .clear, .black.opacity(0.46)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }

    private var legacyBackground: some View {
        LinearGradient(
            colors: [liquidPalette[0].opacity(0.38), liquidPalette[1].opacity(0.24), .black],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .background(Color.black)
        .allowsHitTesting(false)
    }

    private var liquidPalette: [Color] {
        let source = colors.isEmpty ? [Color.indigo, .pink, .purple] : colors
        return (0..<3).map { source[$0 % source.count] }
    }

    @available(macOS 15.0, *)
    private func meshPoints(at time: TimeInterval) -> [SIMD2<Float>] {
        let topLeftX = 0.33 + Float(sin(time * 0.78 + 0.4)) * 0.14
        let topRightX = 0.67 + Float(cos(time * 0.69 + 1.1)) * 0.14
        let bottomLeftX = 0.33 + Float(cos(time * 0.74 + 0.8)) * 0.14
        let bottomRightX = 0.67 + Float(sin(time * 0.83 + 1.6)) * 0.14

        let upperLeftY = 0.33 + Float(cos(time * 0.8 + 0.7)) * 0.14
        let lowerLeftY = 0.67 + Float(sin(time * 0.67 + 1.9)) * 0.14
        let upperRightY = 0.33 + Float(sin(time * 0.86 + 1.2)) * 0.14
        let lowerRightY = 0.67 + Float(cos(time * 0.72 + 2.1)) * 0.14

        let innerUpperLeft = SIMD2<Float>(
            0.31 + Float(sin(time * 1.02 + 0.2)) * 0.16,
            0.31 + Float(cos(time * 0.9 + 1.3)) * 0.16
        )
        let innerUpperRight = SIMD2<Float>(
            0.69 + Float(cos(time * 0.96 + 0.8)) * 0.16,
            0.35 + Float(sin(time * 0.82 + 2.2)) * 0.16
        )
        let innerLowerLeft = SIMD2<Float>(
            0.35 + Float(cos(time * 0.88 + 1.7)) * 0.16,
            0.69 + Float(sin(time * 1.0 + 0.5)) * 0.16
        )
        let innerLowerRight = SIMD2<Float>(
            0.67 + Float(sin(time * 0.94 + 2.4)) * 0.16,
            0.65 + Float(cos(time * 0.86 + 0.9)) * 0.16
        )

        return [
            SIMD2(0, 0), SIMD2(topLeftX, 0), SIMD2(topRightX, 0), SIMD2(1, 0),
            SIMD2(0, upperLeftY), innerUpperLeft, innerUpperRight, SIMD2(1, upperRightY),
            SIMD2(0, lowerLeftY), innerLowerLeft, innerLowerRight, SIMD2(1, lowerRightY),
            SIMD2(0, 1), SIMD2(bottomLeftX, 1), SIMD2(bottomRightX, 1), SIMD2(1, 1)
        ]
    }
}
