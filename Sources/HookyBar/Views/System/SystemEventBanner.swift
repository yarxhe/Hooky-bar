import SwiftUI

/// Нижнее содержимое общей поверхности VPN, Bluetooth, Calendar, AirDrop и Pomodoro.
/// Собственного фона и анимации здесь нет: геометрия всего острова движется как одно целое.
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
    }
}
