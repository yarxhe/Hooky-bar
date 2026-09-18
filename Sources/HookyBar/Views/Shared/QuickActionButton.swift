import SwiftUI

private final class QuickActionInteraction: ObservableObject {
    @Published var hovering = false
}

/// Общая геометрия быстрых действий в Dev и Утилитах.
struct QuickActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var interaction = QuickActionInteraction()

    var body: some View {
        Button {
            HookyDiagnostics.control("action=quick_action phase=request id=\(symbol)")
            action()
            HookyDiagnostics.control("action=quick_action phase=dispatched id=\(symbol)")
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .frame(height: 16)
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(.white.opacity(isEnabled ? 0.9 : 0.4))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            // Scrolling several independent blur layers is expensive in AppKit.
            // The panel already owns the dark material; cards only need a
            // lightweight translucent fill above it.
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(interaction.hovering && isEnabled ? 0.2 : 0), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(SpringPressButtonStyle())
        .onHover { interaction.hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: interaction.hovering)
        .help(title)
    }
}
