import SwiftUI

/// Самостоятельная Dev-страница. Прокрутка оставляет место для будущих CI/SDK-модулей.
struct DeveloperPane: View {
    @ObservedObject var tools: ToolsStore

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 8) {
                projectCard
                commandCard
                actionRow
                githubActivityCard
                // Даёт реальный запас прокрутки: нижние действия можно поднять над краем острова.
                Color.clear.frame(height: 54)
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled(false)
        .scrollBounceBehavior(.basedOnSize)
        .onAppear(perform: tools.refreshDeveloperWorkspace)
    }

    private var projectCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            if tools.workspace.isConfigured {
                workspaceHeader

                if !tools.workspace.lastCommit.isEmpty {
                    Text(tools.workspace.lastCommit)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.42))
                        .lineLimit(1)
                        .padding(.horizontal, 2)
                }

                HStack(spacing: 5) {
                    gitMetric(L10n.tr("dev.changedShort"), tools.workspace.changedFiles, "pencil.line")
                    gitMetric(L10n.tr("dev.untrackedShort"), tools.workspace.untrackedFiles, "plus")
                    gitMetric(L10n.tr("dev.ahead"), tools.workspace.ahead, "arrow.up")
                    gitMetric(L10n.tr("dev.behind"), tools.workspace.behind, "arrow.down")
                    gitMetric(L10n.tr("dev.stash"), tools.workspace.stashCount, "tray.full")
                }
                activityStatusRow
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

    private var activityStatusRow: some View {
        Button(action: tools.openDeveloperActivity) {
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
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(maxWidth: 94, alignment: .trailing)
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

    private var commandCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label(L10n.tr("dev.commands"), systemImage: "play.rectangle")
                    .font(.system(size: 9.5, weight: .bold))
                Spacer(minLength: 0)
                Text(commandStatus)
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(commandStatusColor.opacity(0.85))
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                commandButton(.run, L10n.tr("dev.command.run"), "play.fill")
                commandButton(.test, L10n.tr("dev.command.test"), "checkmark.circle")
                commandButton(.build, L10n.tr("dev.command.build"), "hammer.fill")
            }

            if let outputLine = commandOutputLine {
                Text(outputLine)
                    .font(.system(size: 7.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.38))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .hookyGlass(cornerRadius: 13)
        .opacity(tools.workspace.isConfigured ? 1 : 0.38)
    }

    private func commandButton(
        _ command: DeveloperCommandKind,
        _ title: String,
        _ symbol: String
    ) -> some View {
        let active = tools.developerCommand.lastCommand == command
            && tools.developerCommand.state == .running
        let available = tools.developerCommand.isAvailable(command)
        return Button {
            tools.runDeveloperCommand(command)
        } label: {
            HStack(spacing: 5) {
                if active {
                    Image(systemName: "stop.fill")
                } else {
                    Image(systemName: symbol)
                }
                Text(active ? L10n.tr("dev.command.stop") : title)
                    .lineLimit(1)
            }
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(commandColor(for: command))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(SpringPressButtonStyle())
        .disabled(!available || (tools.developerCommand.state == .running && !active))
        .opacity(available ? 1 : 0.3)
    }

    private var githubActivityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(L10n.tr("dev.github.activity"), systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 9.5, weight: .bold))
                Spacer()
                if tools.developerGitHubActivity.openIssueCount > 0 {
                    Text(L10n.tr("dev.github.openIssues.format", tools.developerGitHubActivity.openIssueCount))
                        .font(.system(size: 7.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }

            if tools.developerGitHubActivity.issues.isEmpty {
                githubActivityRow(
                    nil,
                    fallbackTitle: L10n.tr("dev.github.noIssues"),
                    symbol: "exclamationmark.circle",
                    action: tools.openDeveloperIssues
                )
            } else {
                ForEach(Array(tools.developerGitHubActivity.issues.prefix(2))) { issue in
                    githubActivityRow(
                        issue,
                        fallbackTitle: "",
                        symbol: "exclamationmark.circle",
                        action: { tools.openDeveloperGitHubItem(issue) }
                    )
                }
            }
            githubActivityRow(
                tools.developerGitHubActivity.latestRelease,
                fallbackTitle: L10n.tr("dev.github.noReleases"),
                symbol: "tag",
                action: tools.openDeveloperRelease
            )
            githubActivityRow(
                tools.developerGitHubActivity.pullRequestDiscussion,
                fallbackTitle: L10n.tr("dev.github.noPullRequest"),
                symbol: "text.bubble",
                action: tools.openDeveloperDiscussion
            )
        }
        .padding(10)
        .hookyGlass(cornerRadius: 13)
        .opacity(tools.workspace.isConfigured ? 1 : 0.38)
    }

    private func githubActivityRow(
        _ item: DeveloperGitHubActivityItem?,
        fallbackTitle: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item?.title ?? fallbackTitle)
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(item == nil ? 0.4 : 0.86))
                        .lineLimit(1)
                    if let subtitle = item?.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 7.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.white.opacity(item == nil ? 0.12 : 0.25))
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(SpringPressButtonStyle())
        .disabled(item == nil)
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

    private func gitMetric(_ title: String, _ value: Int, _ symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 7.5, weight: .bold)).foregroundStyle(.white.opacity(0.36))
                Text("\(value)").font(.system(size: 8.5, weight: .semibold, design: .monospaced)).lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
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
        if tools.developerCI.kind == .pullRequest {
            return "arrow.triangle.branch"
        }
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

    private var commandStatus: String {
        guard !tools.developerCommand.toolchain.isEmpty else {
            return L10n.tr("dev.command.notDetected")
        }
        switch tools.developerCommand.state {
        case .idle: return tools.developerCommand.toolchain
        case .running: return L10n.tr("dev.command.running")
        case .success: return L10n.tr("dev.command.success")
        case .failure: return L10n.tr("dev.command.failure")
        case .cancelled: return L10n.tr("dev.command.cancelled")
        }
    }

    private var commandStatusColor: Color {
        switch tools.developerCommand.state {
        case .running: return .blue
        case .success: return .green
        case .failure: return .red
        case .cancelled: return .orange
        case .idle: return .white
        }
    }

    private func commandColor(for command: DeveloperCommandKind) -> Color {
        guard tools.developerCommand.lastCommand == command else { return .white.opacity(0.8) }
        return commandStatusColor.opacity(0.95)
    }

    private var commandOutputLine: String? {
        guard tools.developerCommand.state != .running else { return nil }
        return tools.developerCommand.output
            .split(separator: "\n")
            .last
            .map(String.init)
    }
}
