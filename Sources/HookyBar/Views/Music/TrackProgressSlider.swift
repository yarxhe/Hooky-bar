import Cocoa
import SwiftUI

final class TrackProgressSliderState: ObservableObject {
    @Published var dragValue: Double?
    @Published var hovering = false

    func begin(at value: Double) {
        guard dragValue == nil else { return }
        dragValue = value
    }

    func update(to value: Double) {
        dragValue = value
    }

    func finish() {
        dragValue = nil
    }
}

struct TrackProgressSlider: View {
    let value: Double
    let duration: Double
    let onBegin: () -> Void
    let onScrub: (Double) -> Void
    let onEnd: (Double) -> Void

    @StateObject private var interaction = TrackProgressSliderState()

    private var activeValue: Double {
        min(max(0, interaction.dragValue ?? value), max(1, duration))
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(1, proxy.size.width)
            let safeDuration = max(1, duration)
            let progress = CGFloat(activeValue / safeDuration)
            let thumbSize: CGFloat = interaction.dragValue == nil ? 9 : 11
            let thumbCenter = min(max(thumbSize / 2, width * progress), width - thumbSize / 2)
            let bubbleCenter = min(max(24, thumbCenter), max(24, width - 24))
            let trackHeight = PlaybackSliderStyle.thickness

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(PlaybackSliderStyle.track)
                    .frame(height: trackHeight)
                    .position(x: width / 2, y: 25)

                Capsule()
                    .fill(PlaybackSliderStyle.fill)
                    .frame(width: max(trackHeight, width * progress), height: trackHeight)
                    .position(x: max(trackHeight, width * progress) / 2, y: 25)

                Circle().fill(PlaybackSliderStyle.thumb)
                .frame(width: thumbSize, height: thumbSize)
                .position(x: thumbCenter, y: 25)
                .opacity(interaction.hovering || interaction.dragValue != nil ? 1 : 0.78)

                Text(time(activeValue))
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.94), in: Capsule())
                    .overlay { Capsule().stroke(.white.opacity(0.14), lineWidth: 0.7) }
                    .fixedSize()
                    .position(x: bubbleCenter, y: 7)
                    .opacity(interaction.dragValue == nil ? 0 : 1)
            }
            .contentShape(Rectangle())
            .onHover { inside in
                withAnimation(.smooth(duration: 0.16)) {
                    interaction.hovering = inside
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { gesture in
                        guard duration > 0 else { return }
                        let x = gesture.location.x
                        let target = Double(min(1, max(0, x / width))) * duration
                        if interaction.dragValue == nil {
                            interaction.begin(at: target)
                            onBegin()
                        }
                        interaction.update(to: target)
                        onScrub(target)
                    }
                    .onEnded { _ in
                        let final = activeValue
                        onEnd(final)
                        interaction.finish()
                    }
            )
        }
        .frame(height: 34)
    }

    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let value = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
