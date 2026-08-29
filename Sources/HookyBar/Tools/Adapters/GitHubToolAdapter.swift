import AppKit

/// Маршрутизирует GitHub-действия, не смешивая UI, CLI-чтение и модели.
final class GitHubToolAdapter: ToolActionAdapter {
    let supportedActions: Set<ToolAction> = [
        .openDeveloperRepository,
        .openDeveloperActivity,
        .openDeveloperIssues,
        .openDeveloperRelease,
        .openDeveloperDiscussion
    ]
    let capability = IntegrationCapabilityDeclaration(id: "utilities.github")

    private var status = DeveloperCISnapshot()
    private var activity = DeveloperGitHubActivitySnapshot()

    func perform(_ action: ToolAction) -> IntegrationResult {
        let url: URL?
        switch action {
        case .openDeveloperRepository:
            url = status.repositoryURL
        case .openDeveloperActivity:
            url = status.runURL ?? status.repositoryURL?.appendingPathComponent("actions")
        case .openDeveloperIssues:
            url = activity.latestIssue?.url ?? status.repositoryURL?.appendingPathComponent("issues")
        case .openDeveloperRelease:
            url = activity.latestRelease?.url ?? status.repositoryURL?.appendingPathComponent("releases")
        case .openDeveloperDiscussion:
            url = activity.pullRequestDiscussion?.url
        default:
            return .failed(.unsupported)
        }
        guard let url else { return .failed(.unavailable) }
        return open(url)
    }

    func inspectWorkspace(at workspaceURL: URL, completion: @escaping (DeveloperCISnapshot) -> Void) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let nextStatus = GitHubStatusReader.read(at: workspaceURL)
            DispatchQueue.main.async {
                self?.status = nextStatus
                completion(nextStatus)
            }
        }
    }

    func inspectActivity(
        at workspaceURL: URL,
        completion: @escaping (DeveloperGitHubActivitySnapshot) -> Void
    ) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let nextActivity = GitHubActivityReader.read(at: workspaceURL)
            DispatchQueue.main.async {
                self?.activity = nextActivity
                completion(nextActivity)
            }
        }
    }

    func open(_ item: DeveloperGitHubActivityItem) -> IntegrationResult {
        open(item.url)
    }

    func clear() {
        status = DeveloperCISnapshot()
        activity = DeveloperGitHubActivitySnapshot()
    }

    private func open(_ url: URL) -> IntegrationResult {
        NSWorkspace.shared.open(url) ? .success : .failed(.commandRejected)
    }
}
