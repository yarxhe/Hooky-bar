import SwiftUI

/// Самостоятельная Dev-страница. Прокрутка оставляет место для будущих CI/SDK-модулей.
struct DeveloperPane: View {
    @ObservedObject var tools: ToolsStore

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                projectCard
                actionRow
                // Даёт реальный запас прокрутки: нижние действия можно поднять над краем острова.
                Color.clear.frame(height: 54)
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .onAppear(perform: tools.refreshDeveloperWorkspace)
    }

    private var projectCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            if tools.workspace.isConfigured {
                workspaceHeader
                HStack(spacing: 6) {
                    gitBadge(L10n.tr("dev.changed"), "\(tools.workspace.changedFiles)", "pencil.line")
                    gitBadge(L10n.tr("dev.untracked"), "\(tools.workspace.untrackedFiles)", "plus")
                }
                ciStatusRow
            } else {
                Button(action: tools.chooseDeveloperWorkspace) {
                    Label(L10n.tr("dev.chooseProject"), systemImage: "folder.badge.plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(SpringPressButtonStyle())
            }
        }
        .padding(10)
        .hookyGlass(cornerRadius: 13)
    }

    private var workspaceHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.blue.opacity(0.86))
                .frame(width: 30, height: 30)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(tools.workspace.folderName)
                    .font(.system(size: 11, weight: .bold))
                    .lineLimit(1)
                Text(tools.workspace.branch)
                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let status = tools.status {
                Text(status)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }
            Button(action: tools.chooseDeveloperWorkspace) {
                Label(L10n.tr("dev.change"), systemImage: "folder.badge.plus")
                    .font(.system(size: 8.5, weight: .semibold))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 0.7))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(SpringPressButtonStyle())
            .help(L10n.tr("dev.changeHelp"))

            Button(action: tools.refreshDeveloperWorkspace) {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
                    .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 0.7))
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(SpringPressButtonStyle())
            .help(L10n.tr("dev.refreshHelp"))
        }
    }

    private var ciStatusRow: some View {
        Button(action: tools.openLatestWorkflow) {
            HStack(spacing: 8) {
                Image(systemName: ciSymbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(ciColor)
                    .frame(width: 28, height: 28)
                    .background(ciColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(tools.developerCI.workflow)
                        .font(.system(size: 9.5, weight: .bold))
                        .lineLimit(1)
                    Text(ciSubtitle)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.43))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(tools.developerCI.status)
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(ciColor.opacity(0.9))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(SpringPressButtonStyle())
        .frame(maxWidth: .infinity)
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            quickButton(tools.selectedIDE.title, tools.selectedIDE.symbol, action: tools.openWorkspaceInIDE)
            quickButton(L10n.tr("dev.terminal"), "terminal", action: tools.openWorkspaceInTerminal)
            quickButton("GitHub", "arrow.up.right.square", action: tools.openDeveloperRepository)
            quickButton(L10n.tr("dev.path"), "doc.on.doc", action: tools.copyWorkspacePath)
        }
        .opacity(tools.workspace.isConfigured ? 1 : 0.38)
    }

    private func quickButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                Text(title).font(.system(size: 8.5, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.84))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .hookyGlass(
                cornerRadius: 10,
                interactive: true
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(SpringPressButtonStyle())
    }

    private func gitBadge(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 7.5, weight: .bold)).foregroundStyle(.white.opacity(0.36))
                Text(value).font(.system(size: 8.5, weight: .semibold, design: .monospaced)).lineLimit(1)
            }
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 29)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var ciSubtitle: String {
        let title = tools.developerCI.title
        guard !tools.developerCI.branch.isEmpty else { return title }
        return "\(title) · \(tools.developerCI.branch)"
    }

    private var ciColor: Color {
        switch tools.developerCI.state {
        case .success: return .green
        case .failure: return .red
        case .running: return .blue
        case .queued: return .orange
        case .cancelled: return .gray
        case .notConfigured, .unavailable, .noRuns: return .white.opacity(0.55)
        }
    }

    private var ciSymbol: String {
        switch tools.developerCI.state {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        case .running: return "bolt.horizontal.circle.fill"
        case .queued: return "clock.fill"
        case .cancelled: return "minus.circle.fill"
        case .notConfigured: return "arrow.triangle.branch"
        case .unavailable: return "exclamationmark.triangle.fill"
        case .noRuns: return "play.circle"
        }
    }
}
