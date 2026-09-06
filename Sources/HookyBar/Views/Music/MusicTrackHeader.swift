import SwiftUI

/// Один value-snapshot для уходящего и приходящего заголовка.
/// Вложенного keyed-перехода обложки нет: движение задаёт только MusicPane.
struct MusicTrackHeader: View {
    let snapshot: NowPlayingSnapshot
    let source: MusicSource
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                MusicSourceIcon(source: source)
                    .opacity(snapshot.artwork == nil ? 1 : 0)
                if let artwork = snapshot.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipped()
                        .transition(.opacity)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 11))
            // Меняется только при поздней загрузке, не при каждом revision трека.
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: snapshot.artwork != nil)
            Text(snapshot.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
                .frame(height: 16)
            Text(snapshot.artist)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
                .frame(height: 14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .allowsHitTesting(false)
    }
}
