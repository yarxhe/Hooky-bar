import Cocoa
import SwiftUI

struct MusicPane: View {
    @ObservedObject var store: MusicStore
    @ObservedObject var volume: VolumeStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
                // Старый и новый трек занимают одну область во время перехода:
                // VStack не раздвигает ползунки и кнопки на высоту второй обложки.
                ZStack {
                    MusicTrackHeader(snapshot: store.nowPlaying, source: store.selectedMusicSource)
                        .id(store.trackPresentationRevision)
                        .transition(trackTransition(direction: store.trackNavigationDirection))
                }
                .frame(height: 88)
                .clipped()
                .allowsHitTesting(false)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: store.trackPresentationRevision)

                VStack(spacing: 0) {
                    TrackProgressSlider(
                        value: store.nowPlaying.elapsed,
                        duration: store.nowPlaying.duration,
                        onBegin: { store.beginScrubbing() },
                        onScrub: { store.previewScrubbing(at: $0) },
                        onEnd: { store.finishScrubbing(at: $0) }
                    )
                    HStack {
                        Text(time(store.nowPlaying.elapsed))
                        Spacer()
                        Text(time(store.nowPlaying.duration))
                    }
                    .font(.system(size: 9, weight: .regular))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.48))
                }

                ElasticVolumeSlider(
                    value: volume.level
                ) { volume.setLevel($0) }
                .frame(width: 190)

                ZStack {
                    HStack(spacing: 10) {
                        AnimatedControlButton(icon: "backward.end.fill", size: 17) { store.previousTrack() }
                            .accessibilityLabel(L10n.tr("music.previous"))
                            .help(L10n.tr("music.previous"))
                        Button {
                            store.togglePlayback()
                        } label: {
                            Image(systemName: store.nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 25, weight: .bold))
                                .frame(width: 60, height: 46)
                                .hookyMaterial(
                                    cornerRadius: 15
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .contentTransition(.symbolEffect(.replace.downUp))
                        }.buttonStyle(SpringPressButtonStyle.music)
                        .accessibilityLabel(L10n.tr(store.nowPlaying.isPlaying ? "music.pause" : "music.play"))
                        .help(L10n.tr(store.nowPlaying.isPlaying ? "music.pause" : "music.play"))
                        AnimatedControlButton(icon: "forward.end.fill", size: 17) { store.nextTrack() }
                            .accessibilityLabel(L10n.tr("music.next"))
                            .help(L10n.tr("music.next"))
                    }
                    HStack {
                        if store.canDislike {
                            Button { store.toggleDislike() } label: {
                                Image(systemName: store.nowPlaying.isDisliked ? "heart.slash.fill" : "heart.slash")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(store.nowPlaying.isDisliked ? Color.red.opacity(0.9) : Color.white.opacity(0.65))
                                    .frame(width: 44, height: 42)
                                    .hookyMaterial(cornerRadius: 13)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(SpringPressButtonStyle.music)
                            .help(L10n.tr("music.dislike"))
                        }
                        Spacer()
                        Button { store.toggleLike() } label: {
                            Image(systemName: store.nowPlaying.isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(store.nowPlaying.isLiked ? Color.red : Color.white.opacity(0.65))
                                .shadow(
                                    color: store.nowPlaying.isLiked ? Color.red.opacity(0.85) : .clear,
                                    radius: store.nowPlaying.isLiked ? 7 : 0
                                )
                                .frame(width: 44, height: 42)
                                .hookyMaterial(
                                    cornerRadius: 13
                                )
                                .contentTransition(.symbolEffect(.replace))
                                .animation(reduceMotion ? nil : .snappy(duration: 0.20), value: store.nowPlaying.isLiked)
                        }
                        .buttonStyle(SpringPressButtonStyle.music)
                        .help(L10n.tr("music.like"))
                    }
                }
        }
        .padding(.horizontal, 20).padding(.vertical, 7)
    }

    private func trackTransition(direction: Int) -> AnyTransition {
        let offset: CGFloat = reduceMotion ? 0 : (direction > 0 ? 24 : -24)
        return .asymmetric(
            insertion: .offset(x: offset).combined(with: .opacity),
            removal: .offset(x: -offset).combined(with: .opacity)
        )
    }

    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let value = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct SpringPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pressedScale: CGFloat = 0.96
    var pressedOpacity: Double = 0.85
    var dampingFraction: Double = 0.82

    static let music = SpringPressButtonStyle(
        pressedScale: 0.84, pressedOpacity: 0.66, dampingFraction: 0.58
    )

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: configuration.isPressed)
    }
}

struct AnimatedControlButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 56, height: 44)
                .hookyMaterial(cornerRadius: 14)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(SpringPressButtonStyle.music)
    }
}
