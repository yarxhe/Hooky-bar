import AppKit

/// Читает состояние GitHub через уже авторизованный `gh` и не хранит токены внутри Hooky bar.
final class GitHubToolAdapter: ToolActionAdapter {
    let supportedActions: Set<ToolAction> = [
        .openDeveloperRepository,
        .openLatestWorkflow
    ]
    let capability = IntegrationCapabilityDeclaration(id: "utilities.github")

    private var snapshot = DeveloperCISnapshot()

    func perform(_ action: ToolAction) -> IntegrationResult {
        let url: URL?
        switch action {
        case .openDeveloperRepository:
            url = snapshot.repositoryURL
        case .openLatestWorkflow:
            url = snapshot.runURL ?? snapshot.repositoryURL?.appendingPathComponent("actions")
        default:
            return .failed(.unsupported)
        }
        guard let url else { return .failed(.unavailable) }
        return NSWorkspace.shared.open(url) ? .success : .failed(.commandRejected)
    }

    func inspectWorkspace(at workspaceURL: URL, completion: @escaping (DeveloperCISnapshot) -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let nextSnapshot = Self.makeSnapshot(at: workspaceURL)
            DispatchQueue.main.async {
                self?.snapshot = nextSnapshot
                completion(nextSnapshot)
            }
        }
    }

    func clear() {
        snapshot = DeveloperCISnapshot()
    }

    private static func makeSnapshot(at workspaceURL: URL) -> DeveloperCISnapshot {
        guard let remote = run(
            executable: "/usr/bin/git",
            arguments: ["-C", workspaceURL.path, "remote", "get-url", "origin"]
        ), let repository = repositorySlug(from: remote) else {
            return DeveloperCISnapshot()
        }

        let repositoryURL = URL(string: "https://github.com/\(repository)")
        guard let gh = ghExecutable else {
            return DeveloperCISnapshot(
                repository: repository,
                workflow: "GitHub Actions",
                title: L10n.tr("dev.ci.cliMissing"),
                branch: "",
                status: L10n.tr("dev.ci.installCLI"),
                state: .unavailable,
                repositoryURL: repositoryURL
            )
        }

        let fields = "displayTitle,workflowName,status,conclusion,url,headBranch"
        guard let output = run(
            executable: gh,
            arguments: ["run", "list", "--repo", repository, "--limit", "1", "--json", fields]
        ), let data = output.data(using: .utf8),
              let runs = try? JSONDecoder().decode([WorkflowRun].self, from: data) else {
            return DeveloperCISnapshot(
                repository: repository,
                workflow: "GitHub Actions",
                title: L10n.tr("dev.ci.readFailed"),
                branch: "",
                status: L10n.tr("dev.ci.checkAuth"),
                state: .unavailable,
                repositoryURL: repositoryURL
            )
        }

        guard let run = runs.first else {
            return DeveloperCISnapshot(
                repository: repository,
                workflow: "GitHub Actions",
                title: L10n.tr("dev.ci.noRuns"),
                branch: "",
                status: L10n.tr("dev.ci.runWorkflow"),
                state: .noRuns,
                repositoryURL: repositoryURL
            )
        }

        let state = state(status: run.status, conclusion: run.conclusion)
        return DeveloperCISnapshot(
            repository: repository,
            workflow: run.workflowName?.nilIfEmpty ?? "GitHub Actions",
            title: run.displayTitle?.nilIfEmpty ?? L10n.tr("dev.ci.latestBuild"),
            branch: run.headBranch?.nilIfEmpty ?? "",
            status: statusText(for: state),
            state: state,
            repositoryURL: repositoryURL,
            runURL: run.url.flatMap(URL.init(string:))
        )
    }

    private static var ghExecutable: String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private static func repositorySlug(from remote: String) -> String? {
        let value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if value.hasPrefix("git@github.com:") {
            path = String(value.dropFirst("git@github.com:".count))
        } else if let url = URL(string: value), url.host?.lowercased() == "github.com" {
            path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else {
            return nil
        }
        let cleaned = path.hasSuffix(".git") ? String(path.dropLast(4)) : path
        return cleaned.split(separator: "/").count == 2 ? cleaned : nil
    }

    private static func state(status: String?, conclusion: String?) -> DeveloperCIState {
        switch status?.lowercased() {
        case "queued", "pending", "requested", "waiting": return .queued
        case "in_progress": return .running
        case "completed":
            switch conclusion?.lowercased() {
            case "success": return .success
            case "failure", "timed_out", "startup_failure", "action_required": return .failure
            default: return .cancelled
            }
        default: return .unavailable
        }
    }

    private static func statusText(for state: DeveloperCIState) -> String {
        switch state {
        case .queued: return L10n.tr("dev.ci.queued")
        case .running: return L10n.tr("dev.ci.running")
        case .success: return L10n.tr("dev.ci.success")
        case .failure: return L10n.tr("dev.ci.failure")
        case .cancelled: return L10n.tr("dev.ci.cancelled")
        case .notConfigured, .unavailable, .noRuns: return ""
        }
    }

    private static func run(executable: String, arguments: [String]) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct WorkflowRun: Decodable {
    let displayTitle: String?
    let workflowName: String?
    let status: String?
    let conclusion: String?
    let url: String?
    let headBranch: String?
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
