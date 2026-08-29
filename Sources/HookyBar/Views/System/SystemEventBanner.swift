import SwiftUI

/// Единая нижняя карточка для VPN, Bluetooth, Calendar, AirDrop и Pomodoro.
/// Верхние крылья остаются chrome плеера или таймера и не дублируют событие.
struct SystemEventBanner: View {
    let event: HookySystemEvent
    let width: CGFloat

    private var tint: Color {
        Color(nsColor: event.tint)
    }

    var body: some View {
        HStack(spacing: 11) {
            eventIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.96))
                    .lineLimit(1)

                Text(event.subtitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: width, height: 52)
        .background {
            ZStack {
                Color.white.opacity(0.045)
                LinearGradient(
                    colors: [tint.opacity(0.16), tint.opacity(0.045), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private var eventIcon: some View {
        Image(systemName: event.symbol)
            .font(.system(size: 13, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(
                tint.opacity(0.17),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 0.5)
            }
            .symbolEffect(.bounce, value: event.id)
    }
}
