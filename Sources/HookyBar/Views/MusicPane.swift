import Cocoa
import SwiftUI

struct MusicPane: View {
    @ObservedObject var store: MusicStore
    @ObservedObject var volume: VolumeStore

    var body: some View {
        VStack(spacing: 6) {
                trackHeader
                    .id(store.trackPresentationRevision)
                    .transition(trackTransition)
                    .animation(HookyMotion.trackSwitch, value: store.trackPresentationRevision)

                HStack(spacing: 8) {
                    Text(time(store.nowPlaying.elapsed))
                    TrackProgressSlider(
                        value: store.nowPlaying.elapsed,
                        duration: store.nowPlaying.duration,
                        onBegin: { store.beginScrubbing() },
                        onScrub: { store.previewScrubbing(at: $0) },
                        onEnd: { store.finishScrubbing(at: $0) }
                    )
                    Text(time(store.nowPlaying.duration))
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.48))

                ElasticVolumeSlider(
                    value: volume.level
                ) { volume.setLevel($0) }
                .frame(width: 190)

                ZStack {
                    HStack(spacing: 10) {
                        AnimatedControlButton(icon: "backward.end.fill", size: 17) { store.previousTrack() }
                        Button {
                            store.togglePlayback()
                        } label: {
                            Image(systemName: store.nowPlaying.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 25, weight: .bold))
                                .frame(width: 60, height: 46)
                                .hookyGlass(
                                    cornerRadius: 15,
                                    interactive: true
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                                .contentTransition(.symbolEffect(.replace.downUp))
                        }.buttonStyle(SpringPressButtonStyle())
                        AnimatedControlButton(icon: "forward.end.fill", size: 17) { store.nextTrack() }
                    }
                    HStack {
                        if store.canDislike {
                            Button { store.toggleDislike() } label: {
                                Image(systemName: store.nowPlaying.isDisliked ? "heart.slash.fill" : "heart.slash")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(store.nowPlaying.isDisliked ? Color.red.opacity(0.9) : Color.white.opacity(0.65))
                                    .frame(width: 44, height: 42)
                                    .hookyGlass(cornerRadius: 13, interactive: true)
                                    .contentTransition(.symbolEffect(.replace))
                            }
                            .buttonStyle(SpringPressButtonStyle())
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
                                .hookyGlass(
                                    cornerRadius: 13,
                                    interactive: true
                                )
                                .contentTransition(.symbolEffect(.replace))
                                .animation(.spring(response: 0.3, dampingFraction: 0.58), value: store.nowPlaying.isLiked)
                        }
                        .buttonStyle(SpringPressButtonStyle())
                        .help(L10n.tr("music.like"))
                    }
                }
        }
        .padding(.horizontal, 20).padding(.vertical, 7)
    }

    private var trackTransition: AnyTransition {
        let direction = store.trackNavigationDirection
        // Next track (direction > 0): incoming slides in from the right (trailing),
        // outgoing slides out to the left (leading).
        // Previous track (direction < 0): incoming slides in from the left (leading),
        // outgoing slides out to the right (trailing).
        let insertionEdge: Edge = direction > 0 ? .trailing : .leading
        let removalEdge: Edge = direction > 0 ? .leading : .trailing

        return .asymmetric(
            insertion: .move(edge: insertionEdge).combined(with: .opacity),
            removal: .move(edge: removalEdge).combined(with: .opacity)
        )
    }

    private var trackHeader: some View {
        VStack(spacing: 3) {
            ZStack {
                Group {
                    if let artwork = store.nowPlaying.artwork {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        MusicSourceIcon(source: store.selectedMusicSource)
                    }
                }
                .id(store.artworkPresentationRevision)
                .transition(artworkTransition)
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            .animation(HookyMotion.artworkArrival, value: store.artworkPresentationRevision)
            Text(store.nowPlaying.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            Text(store.nowPlaying.artist)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var artworkTransition: AnyTransition {
        let insertionEdge: Edge = store.trackNavigationDirection > 0 ? .trailing : .leading
        let removalEdge: Edge = store.trackNavigationDirection > 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: insertionEdge)
                .combined(with: .scale(scale: 0.9))
                .combined(with: .opacity),
            removal: .move(edge: removalEdge)
                .combined(with: .scale(scale: 0.96))
                .combined(with: .opacity)
        )
    }

    private func time(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let value = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

struct SpringPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .opacity(configuration.isPressed ? 0.66 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.58), value: configuration.isPressed)
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
                .hookyGlass(cornerRadius: 14, interactive: true)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(SpringPressButtonStyle())
    }
}
