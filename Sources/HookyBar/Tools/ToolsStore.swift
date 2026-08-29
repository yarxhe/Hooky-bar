import AppKit
import Combine

/// Маршрутизирует действия через адаптеры и хранит состояние панели инструментов.
final class ToolsStore: ObservableObject {
    @Published private(set) var keepsMacAwake = false
    @Published private(set) var developerModeEnabled: Bool
    @Published private(set) var selectedIDE: DeveloperIDE
    @Published private(set) var workspace = DeveloperWorkspaceSnapshot()
    @Published private(set) var developerCI = DeveloperCISnapshot()
    @Published private(set) var developerCommand = DeveloperCommandSnapshot()
    @Published private(set) var developerGitHubActivity = DeveloperGitHubActivitySnapshot()
    @Published private(set) var status: String?

    private var caffeinateProcess: Process?
    private var adapters: [any ToolActionAdapter]
    private let developerAdapter: DeveloperToolAdapter
    private let githubAdapter: GitHubToolAdapter
    private let commandAdapter: DeveloperCommandAdapter
    private let developerModeKey = "tools.developerMode"

    var utilityCapabilities: [IntegrationCapabilityDeclaration] {
        (adapters.map(\.capability) + [commandAdapter.capability]).sorted { $0.id < $1.id }
    }

    init(defaults: UserDefaults = .standard) {
        developerModeEnabled = defaults.bool(forKey: developerModeKey)
        let developerAdapter = DeveloperToolAdapter(defaults: defaults)
        selectedIDE = developerAdapter.selectedIDE
        let githubAdapter = GitHubToolAdapter()
        let commandAdapter = DeveloperCommandAdapter()
        self.developerAdapter = developerAdapter
        self.githubAdapter = githubAdapter
        self.commandAdapter = commandAdapter
        adapters = [SystemToolAdapter(), developerAdapter, githubAdapter]
    }

    func setDeveloperModeEnabled(_ enabled: Bool) {
        developerModeEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: developerModeKey)
    }

    func selectDeveloperIDE(_ ide: DeveloperIDE) {
        selectedIDE = ide
        developerAdapter.selectIDE(ide)
    }

    func isDeveloperIDEInstalled(_ ide: DeveloperIDE) -> Bool {
        developerAdapter.isInstalled(ide)
    }

    func toggleKeepAwake() {
        keepsMacAwake ? stopKeepingAwake() : startKeepingAwake()
    }

    func openCalendar() {
        perform(.openCalendar)
    }

    func openDownloads() {
        perform(.openDownloads)
    }

    func chooseDeveloperWorkspace() {
        developerAdapter.chooseWorkspace { [weak self] url in
            guard url != nil else { return }
            self?.refreshDeveloperWorkspace()
        }
    }

    func copyWorkspacePath() {
        showStatus(perform(.copyWorkspacePath).succeeded ? L10n.tr("tools.pathCopied") : L10n.tr("tools.chooseProjectFirst"))
    }

    func openWorkspaceInIDE() {
        guard perform(.openWorkspaceInIDE).succeeded else {
            showStatus(String(format: L10n.tr("tools.ideNotInstalled.format"), selectedIDE.title))
            return
        }
    }

    func openWorkspaceInTerminal() {
        showFailureIfNeeded(perform(.openWorkspaceInTerminal))
    }

    func openWorkspaceInFinder() {
        showFailureIfNeeded(perform(.openWorkspaceInFinder))
    }

    func openDeveloperRepository() {
        if !perform(.openDeveloperRepository).succeeded { showStatus(L10n.tr("tools.noGitHubOrigin")) }
    }

    func openDeveloperActivity() {
        if !perform(.openDeveloperActivity).succeeded { showStatus(L10n.tr("tools.buildUnavailable")) }
    }

    func openDeveloperIssues() {
        showFailureIfNeeded(perform(.openDeveloperIssues))
    }

    func openDeveloperRelease() {
        showFailureIfNeeded(perform(.openDeveloperRelease))
    }

    func openDeveloperDiscussion() {
        showFailureIfNeeded(perform(.openDeveloperDiscussion))
    }

    func openDeveloperGitHubItem(_ item: DeveloperGitHubActivityItem) {
        showFailureIfNeeded(githubAdapter.open(item))
    }

    func runDeveloperCommand(_ command: DeveloperCommandKind) {
        guard let workspaceURL = developerAdapter.workspaceURL else {
            showStatus(L10n.tr("tools.chooseProjectFirst"))
            return
        }
        if developerCommand.state == .running {
            if developerCommand.lastCommand == command { commandAdapter.cancel() }
            return
        }
        guard developerCommand.isAvailable(command) else {
            showStatus(L10n.tr("dev.command.unavailable"))
            return
        }

        developerCommand.lastCommand = command
        developerCommand.state = .running
        developerCommand.output = ""
        guard commandAdapter.run(command, at: workspaceURL, completion: { [weak self] state, output in
            self?.developerCommand.state = state
            self?.developerCommand.output = output
            self?.refreshDeveloperWorkspace()
        }) else {
            developerCommand.state = .failure(-1)
            showStatus(L10n.tr("dev.command.launchFailed"))
            return
        }
    }

    func refreshDeveloperWorkspace() {
        guard developerModeEnabled else { return }
        status = L10n.tr("tools.refreshing")
        developerAdapter.inspectWorkspace { [weak self] snapshot in
            guard let self else { return }
            let workspaceChanged = self.workspace.path != snapshot.path
            self.workspace = snapshot
            guard let workspaceURL = self.developerAdapter.workspaceURL else {
                self.githubAdapter.clear()
                self.developerCI = DeveloperCISnapshot()
                self.developerCommand = DeveloperCommandSnapshot()
                self.developerGitHubActivity = DeveloperGitHubActivitySnapshot()
                self.status = nil
                return
            }
            if workspaceChanged {
                self.developerCI = DeveloperCISnapshot()
                self.developerGitHubActivity = DeveloperGitHubActivitySnapshot()
                self.developerCommand = self.commandAdapter.inspectWorkspace(at: workspaceURL)
            } else if self.developerCommand.state != .running {
                let previous = self.developerCommand
                self.developerCommand = self.commandAdapter.inspectWorkspace(at: workspaceURL)
                self.developerCommand.lastCommand = previous.lastCommand
                self.developerCommand.state = previous.state
                self.developerCommand.output = previous.output
            }
            self.githubAdapter.inspectWorkspace(at: workspaceURL) { [weak self] ciSnapshot in
                self?.developerCI = ciSnapshot
                self?.status = nil
            }
            self.githubAdapter.inspectActivity(at: workspaceURL) { [weak self] activity in
                self?.developerGitHubActivity = activity
            }
        }
    }

    func stop() {
        stopKeepingAwake()
        commandAdapter.stop()
    }

    func refreshLocalizedContent() {
        status = nil
        if workspace.isConfigured {
            refreshDeveloperWorkspace()
        } else {
            workspace = DeveloperWorkspaceSnapshot()
            developerCI = DeveloperCISnapshot()
            developerCommand = DeveloperCommandSnapshot()
            developerGitHubActivity = DeveloperGitHubActivitySnapshot()
        }
    }

    func register(_ adapter: any ToolActionAdapter) {
        adapters.removeAll { $0.capability.id == adapter.capability.id }
        adapters.append(adapter)
    }

    @discardableResult
    private func perform(_ action: ToolAction) -> IntegrationResult {
        adapters.first(where: { $0.supportedActions.contains(action) })?.perform(action)
            ?? .failed(.unsupported)
    }

    private func showStatus(_ value: String) {
        status = value
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard self?.status == value else { return }
            self?.status = nil
        }
    }

    private func showFailureIfNeeded(_ result: IntegrationResult) {
        if !result.succeeded { showStatus(L10n.tr("tools.chooseProjectFirst")) }
    }

    private func startKeepingAwake() {
        guard caffeinateProcess == nil else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-dims", "-w", "\(ProcessInfo.processInfo.processIdentifier)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self, weak process] _ in
            DispatchQueue.main.async {
                guard self?.caffeinateProcess === process else { return }
                self?.caffeinateProcess = nil
                self?.keepsMacAwake = false
            }
        }
        do {
            try process.run()
            caffeinateProcess = process
            keepsMacAwake = true
        } catch {
            caffeinateProcess = nil
            keepsMacAwake = false
        }
    }

    private func stopKeepingAwake() {
        let process = caffeinateProcess
        caffeinateProcess = nil
        process?.terminate()
        keepsMacAwake = false
    }
}
