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
    private var statusGeneration = 0
    private var activityGeneration = 0

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
        statusGeneration &+= 1
        let generation = statusGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let nextStatus = GitHubStatusReader.read(at: workspaceURL)
            DispatchQueue.main.async {
                guard let self, self.statusGeneration == generation else { return }
                self.status = nextStatus
                completion(nextStatus)
            }
        }
    }

    func inspectActivity(
        at workspaceURL: URL,
        completion: @escaping (DeveloperGitHubActivitySnapshot) -> Void
    ) {
        activityGeneration &+= 1
        let generation = activityGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let nextActivity = GitHubActivityReader.read(at: workspaceURL)
            DispatchQueue.main.async {
                guard let self, self.activityGeneration == generation else { return }
                self.activity = nextActivity
                completion(nextActivity)
            }
        }
    }

    /// CI and activity share one repository lookup instead of launching the
    /// same git probes twice for a single Dev refresh.
    func inspectAll(
        at workspaceURL: URL,
        completion: @escaping (DeveloperCISnapshot, DeveloperGitHubActivitySnapshot) -> Void
    ) {
        statusGeneration &+= 1
        activityGeneration &+= 1
        let requestedStatusGeneration = statusGeneration
        let requestedActivityGeneration = activityGeneration
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let context = GitHubCLI.context(at: workspaceURL)
            let nextStatus = GitHubStatusReader.read(context: context)
            let nextActivity = GitHubActivityReader.read(context: context)
            DispatchQueue.main.async {
                guard let self,
                      self.statusGeneration == requestedStatusGeneration,
                      self.activityGeneration == requestedActivityGeneration else { return }
                self.status = nextStatus
                self.activity = nextActivity
                completion(nextStatus, nextActivity)
            }
        }
    }

    func open(_ item: DeveloperGitHubActivityItem) -> IntegrationResult {
        open(item.url)
    }

    func clear() {
        statusGeneration &+= 1
        activityGeneration &+= 1
        status = DeveloperCISnapshot()
        activity = DeveloperGitHubActivitySnapshot()
    }

    private func open(_ url: URL) -> IntegrationResult {
        NSWorkspace.shared.open(url) ? .success : .failed(.commandRejected)
    }
}
