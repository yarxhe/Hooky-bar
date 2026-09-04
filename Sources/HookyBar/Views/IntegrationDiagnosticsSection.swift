import SwiftUI

struct IntegrationDiagnosticsSection: View {
    @ObservedObject var diagnostics: IntegrationDiagnosticsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.tr("settings.diagnostics.title"))
                        .font(.system(size: 16, weight: .semibold))
                    Text(L10n.tr("settings.diagnostics.subtitle"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: diagnostics.copyReport) {
                    Image(systemName: diagnostics.reportCopied ? "checkmark" : "doc.on.doc")
                        .foregroundStyle(diagnostics.reportCopied ? .green : .primary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .disabled(diagnostics.items.isEmpty || diagnostics.isRefreshing)
                .help(L10n.tr(
                    diagnostics.reportCopied
                        ? "settings.diagnostics.reportCopied"
                        : "settings.diagnostics.copyReport"
                ))
                .accessibilityLabel(L10n.tr(
                    diagnostics.reportCopied
                        ? "settings.diagnostics.reportCopied"
                        : "settings.diagnostics.copyReport"
                ))
                Button(action: diagnostics.refresh) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(diagnostics.isRefreshing ? 360 : 0))
                        .animation(
                            diagnostics.isRefreshing
                                ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                : .default,
                            value: diagnostics.isRefreshing
                        )
                }
                .buttonStyle(.borderless)
                .disabled(diagnostics.isRefreshing)
                .help(L10n.tr("settings.diagnostics.refresh"))
            }

            VStack(spacing: 0) {
                ForEach(Array(diagnostics.items.enumerated()), id: \.element.id) { index, item in
                    diagnosticRow(item)
                    if index < diagnostics.items.count - 1 {
                        Divider().padding(.leading, 46)
                    }
                }
            }
            .padding(.horizontal, 12)
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
    }

    private func diagnosticRow(_ item: IntegrationDiagnosticItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: item.symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint(item.status))
                .frame(width: 30, height: 30)
                .background(
                    tint(item.status).opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12, weight: .medium))
                Text(item.detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(item.status.title)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(tint(item.status))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(tint(item.status).opacity(0.11), in: Capsule())
                if item.settingsPermission != nil {
                    Button(L10n.tr("settings.diagnostics.openSettings")) {
                        diagnostics.openSettings(for: item)
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 9))
                }
            }
        }
        .padding(.vertical, 9)
    }

    private func tint(_ status: IntegrationDiagnosticStatus) -> Color {
        switch status {
        case .ready: .green
        case .needsAttention: .orange
        case .unavailable: .red
        case .inactive: .secondary
        case .checkedOnUse: .blue
        }
    }
}
