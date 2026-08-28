import AppKit

final class DeveloperToolAdapter: ToolActionAdapter {
    let supportedActions: Set<ToolAction> = [
        .copyWorkspacePath,
        .openWorkspaceInIDE,
        .openWorkspaceInTerminal,
        .openWorkspaceInFinder
    ]
    let capability = IntegrationCapabilityDeclaration(id: "utilities.developer")

    private(set) var workspaceURL: URL?
    private(set) var selectedIDE: DeveloperIDE
    private let defaults: UserDefaults
    private let workspaceKey = "tools.developerWorkspacePath"
    private let ideKey = "tools.developerIDE"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedIDE = defaults.string(forKey: ideKey)
            .flatMap(DeveloperIDE.init(rawValue:)) ?? .visualStudioCode
        if let path = defaults.string(forKey: workspaceKey), FileManager.default.fileExists(atPath: path) {
            workspaceURL = URL(fileURLWithPath: path, isDirectory: true)
        }
    }

    func perform(_ action: ToolAction) -> IntegrationResult {
        guard let workspaceURL else { return .failed(.invalidConfiguration) }
        switch action {
        case .copyWorkspacePath:
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.setString(workspaceURL.path, forType: .string)
                ? .success : .failed(.commandRejected)
        case .openWorkspaceInIDE:
            guard let bundleIdentifier = installedBundleIdentifier(for: selectedIDE) else {
                return .failed(.notInstalled)
            }
            return open(arguments: ["-b", bundleIdentifier, workspaceURL.path])
        case .openWorkspaceInTerminal:
            return open(arguments: ["-a", "Terminal", workspaceURL.path])
        case .openWorkspaceInFinder:
            return NSWorkspace.shared.open(workspaceURL) ? .success : .failed(.commandRejected)
        default:
            return .failed(.unsupported)
        }
    }

    func selectIDE(_ ide: DeveloperIDE) {
        selectedIDE = ide
        defaults.set(ide.rawValue, forKey: ideKey)
    }

    func isInstalled(_ ide: DeveloperIDE) -> Bool {
        installedBundleIdentifier(for: ide) != nil
    }

    func chooseWorkspace(completion: @escaping (URL?) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = L10n.tr("dev.openPanel.title")
        panel.prompt = L10n.tr("dev.openPanel.prompt")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let workspaceURL { panel.directoryURL = workspaceURL }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else {
                completion(nil)
                return
            }
            guard let self else { return }
            self.workspaceURL = url
            self.defaults.set(url.path, forKey: self.workspaceKey)
            completion(url)
        }
    }

    func inspectWorkspace(completion: @escaping (DeveloperWorkspaceSnapshot) -> Void) {
        guard let workspaceURL else {
            completion(DeveloperWorkspaceSnapshot())
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let status = Self.runGit(["status", "--porcelain=1", "--branch"], at: workspaceURL)
            let commit = Self.runGit(["log", "-1", "--pretty=%h  %s"], at: workspaceURL)
            let snapshot = Self.snapshot(for: workspaceURL, status: status, commit: commit)
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    private func open(arguments: [String]) -> IntegrationResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return .success
        } catch {
            return .failed(.commandRejected)
        }
    }

    private func installedBundleIdentifier(for ide: DeveloperIDE) -> String? {
        ide.bundleIdentifiers.first {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil
        }
    }

    private static func runGit(_ arguments: [String], at folder: URL) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path] + arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func snapshot(for folder: URL, status: String?, commit: String?) -> DeveloperWorkspaceSnapshot {
        guard let status else {
            return DeveloperWorkspaceSnapshot(
                folderName: folder.lastPathComponent,
                path: folder.path,
                branch: L10n.tr("dev.notGitRepository"),
                lastCommit: ""
            )
        }

        let lines = status.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let branchLine = lines.first(where: { $0.hasPrefix("## ") })
        let branch = branchLine
            .map { String($0.dropFirst(3)).components(separatedBy: "...").first ?? "—" }
            ?? "—"
        let files = lines.filter { !$0.hasPrefix("## ") }
        return DeveloperWorkspaceSnapshot(
            folderName: folder.lastPathComponent,
            path: folder.path,
            branch: branch,
            changedFiles: files.filter { !$0.hasPrefix("??") }.count,
            untrackedFiles: files.filter { $0.hasPrefix("??") }.count,
            lastCommit: commit ?? ""
        )
    }
}
