import Cocoa
import SwiftUI

final class ElasticSliderState: ObservableObject {
    @Published var dragValue: CGFloat?
    @Published var overflow: CGFloat = 0
    @Published var region = 0
    @Published var hovering = false
}

struct ElasticVolumeSlider: View {
    let value: CGFloat
    let onChange: (CGFloat) -> Void

    @StateObject private var interaction = ElasticSliderState()

    private var progress: CGFloat { min(1, max(0, interaction.dragValue ?? value)) }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: progress == 0 ? "speaker.slash.fill" : "speaker.fill")
                .offset(x: interaction.region < 0 ? -interaction.overflow * 0.22 : 0)
                .scaleEffect(interaction.region < 0 && interaction.overflow > 1 ? 1.08 : 1)

            GeometryReader { proxy in
                let width = max(1, proxy.size.width)
                let trackHeight: CGFloat = interaction.hovering || interaction.dragValue != nil ? 11 : 6
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(HookyTheme.controlAccent)
                        .frame(width: max(trackHeight, width * progress))
                    Circle()
                        .fill(Color.white)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        .frame(width: trackHeight + 3, height: trackHeight + 3)
                        .offset(x: max(0, min(width - trackHeight - 3, width * progress - (trackHeight + 3) / 2)))
                        .opacity(interaction.hovering || interaction.dragValue != nil ? 1 : 0)
                }
                .frame(height: trackHeight)
                .frame(maxHeight: .infinity)
                .scaleEffect(
                    x: 1 + interaction.overflow / width,
                    y: 1 - min(0.18, interaction.overflow / 280),
                    anchor: interaction.region < 0 ? .trailing : .leading
                )
                .contentShape(Rectangle())
                .onHover { inside in
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.76)) { interaction.hovering = inside }
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { gesture in
                            let x = gesture.location.x
                            if x < 0 {
                                interaction.region = -1
                                interaction.overflow = decay(-x)
                            } else if x > width {
                                interaction.region = 1
                                interaction.overflow = decay(x - width)
                            } else {
                                interaction.region = 0
                                interaction.overflow = 0
                            }
                            let fraction = min(1, max(0, x / width))
                            interaction.dragValue = fraction
                            onChange(fraction)
                        }
                        .onEnded { _ in
                            interaction.dragValue = nil
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.62)) {
                                interaction.overflow = 0
                                interaction.region = 0
                            }
                        }
                )
                .animation(.spring(response: 0.24, dampingFraction: 0.78), value: trackHeight)
            }
            .frame(height: 24)

            Image(systemName: "speaker.wave.3.fill")
                .offset(x: interaction.region > 0 ? interaction.overflow * 0.22 : 0)
                .scaleEffect(interaction.region > 0 && interaction.overflow > 1 ? 1.08 : 1)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.white.opacity(0.5))
    }

    private func decay(_ value: CGFloat) -> CGFloat {
        let maximum: CGFloat = 50
        let entry = value / maximum
        return 2 * (1 / (1 + exp(-entry)) - 0.5) * maximum
    }

}
