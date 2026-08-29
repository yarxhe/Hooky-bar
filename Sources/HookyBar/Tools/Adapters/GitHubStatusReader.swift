import Foundation

/// Читает только текущий PR и CI-состояние выбранной ветки.
enum GitHubStatusReader {
    static func read(at workspaceURL: URL) -> DeveloperCISnapshot {
        guard let context = GitHubCLI.context(at: workspaceURL) else {
            return DeveloperCISnapshot()
        }
        guard let gh = context.ghExecutable else {
            return DeveloperCISnapshot(
                repository: context.repository,
                workflow: "GitHub Actions",
                title: L10n.tr("dev.ci.cliMissing"),
                branch: "",
                status: L10n.tr("dev.ci.installCLI"),
                state: .unavailable,
                repositoryURL: context.repositoryURL
            )
        }
        if let pullRequest = currentPullRequest(context: context, gh: gh) {
            return pullRequestSnapshot(
                pullRequest,
                checks: pullRequestChecks(context: context, gh: gh),
                context: context
            )
        }
        return workflowSnapshot(context: context, gh: gh)
    }

    private static func workflowSnapshot(
        context: GitHubRepositoryContext,
        gh: String
    ) -> DeveloperCISnapshot {
        let fields = "displayTitle,workflowName,status,conclusion,url,headBranch"
        guard let output = GitHubCLI.run(
            executable: gh,
            arguments: ["run", "list", "--repo", context.repository, "--limit", "1", "--json", fields]
        ), let data = output.data(using: .utf8),
              let runs = try? JSONDecoder().decode([WorkflowRun].self, from: data) else {
            return unavailableSnapshot(context: context)
        }
        guard let run = runs.first else {
            return DeveloperCISnapshot(
                repository: context.repository,
                workflow: "GitHub Actions",
                title: L10n.tr("dev.ci.noRuns"),
                branch: "",
                status: L10n.tr("dev.ci.runWorkflow"),
                state: .noRuns,
                repositoryURL: context.repositoryURL
            )
        }
        let runState = state(status: run.status, conclusion: run.conclusion)
        return DeveloperCISnapshot(
            repository: context.repository,
            kind: .workflow,
            workflow: run.workflowName?.nilIfEmpty ?? "GitHub Actions",
            title: run.displayTitle?.nilIfEmpty ?? L10n.tr("dev.ci.latestBuild"),
            branch: run.headBranch?.nilIfEmpty ?? "",
            status: statusText(for: runState),
            state: runState,
            repositoryURL: context.repositoryURL,
            runURL: run.url.flatMap(URL.init(string:))
        )
    }

    private static func currentPullRequest(
        context: GitHubRepositoryContext,
        gh: String
    ) -> PullRequest? {
        guard !context.branch.isEmpty else { return nil }
        let fields = "number,title,url,isDraft,reviewDecision,mergeStateStatus"
        guard let output = GitHubCLI.run(
            executable: gh,
            arguments: [
                "pr", "list", "--repo", context.repository, "--head", context.branch,
                "--state", "open", "--limit", "1", "--json", fields
            ]
        ), let data = output.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([PullRequest].self, from: data).first
    }

    private static func pullRequestChecks(
        context: GitHubRepositoryContext,
        gh: String
    ) -> PullRequestCheckSummary {
        guard let output = GitHubCLI.run(
            executable: gh,
            arguments: [
                "pr", "checks", context.branch, "--repo", context.repository, "--json", "bucket"
            ],
            acceptedExitCodes: [0, 1, 8]
        ), let data = output.data(using: .utf8),
              let checks = try? JSONDecoder().decode([PullRequestCheck].self, from: data) else {
            return PullRequestCheckSummary()
        }
        return PullRequestCheckSummary(
            passed: checks.filter { $0.bucket == "pass" || $0.bucket == "skipping" }.count,
            failed: checks.filter { $0.bucket == "fail" || $0.bucket == "cancel" }.count,
            pending: checks.filter { $0.bucket == "pending" }.count,
            total: checks.count
        )
    }

    private static func pullRequestSnapshot(
        _ pullRequest: PullRequest,
        checks: PullRequestCheckSummary,
        context: GitHubRepositoryContext
    ) -> DeveloperCISnapshot {
        let presentation = pullRequestPresentation(pullRequest, checks: checks)
        return DeveloperCISnapshot(
            repository: context.repository,
            kind: .pullRequest,
            workflow: "PR #\(pullRequest.number)",
            title: pullRequest.title,
            branch: "",
            status: presentation.status,
            state: presentation.state,
            repositoryURL: context.repositoryURL,
            runURL: URL(string: pullRequest.url)
        )
    }

    private static func pullRequestPresentation(
        _ pullRequest: PullRequest,
        checks: PullRequestCheckSummary
    ) -> (status: String, state: DeveloperCIState) {
        if pullRequest.isDraft { return (L10n.tr("dev.pr.draft"), .queued) }
        if pullRequest.mergeStateStatus == "DIRTY" { return (L10n.tr("dev.pr.conflicts"), .failure) }
        if checks.failed > 0 {
            return (L10n.tr("dev.pr.checksFailed.format", checks.failed), .failure)
        }
        if checks.pending > 0 {
            return (L10n.tr("dev.pr.checksPending.format", checks.pending), .running)
        }
        if pullRequest.reviewDecision == "CHANGES_REQUESTED" {
            return (L10n.tr("dev.pr.changesRequested"), .failure)
        }

        let checksText = checks.total > 0
            ? L10n.tr("dev.pr.checks.format", checks.passed, checks.total) : ""
        if pullRequest.reviewDecision == "APPROVED" {
            let status = checksText.isEmpty
                ? L10n.tr("dev.pr.approved")
                : "\(checksText) · \(L10n.tr("dev.pr.approved"))"
            return (status, .success)
        }
        let status = checksText.isEmpty
            ? L10n.tr("dev.pr.reviewRequired")
            : "\(checksText) · \(L10n.tr("dev.pr.reviewRequired"))"
        return (status, .queued)
    }

    private static func unavailableSnapshot(context: GitHubRepositoryContext) -> DeveloperCISnapshot {
        DeveloperCISnapshot(
            repository: context.repository,
            workflow: "GitHub Actions",
            title: L10n.tr("dev.ci.readFailed"),
            branch: "",
            status: L10n.tr("dev.ci.checkAuth"),
            state: .unavailable,
            repositoryURL: context.repositoryURL
        )
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
}

private struct WorkflowRun: Decodable {
    let displayTitle: String?
    let workflowName: String?
    let status: String?
    let conclusion: String?
    let url: String?
    let headBranch: String?
}

private struct PullRequest: Decodable {
    let number: Int
    let title: String
    let url: String
    let isDraft: Bool
    let reviewDecision: String?
    let mergeStateStatus: String?
}

private struct PullRequestCheck: Decodable {
    let bucket: String
}

private struct PullRequestCheckSummary {
    var passed = 0
    var failed = 0
    var pending = 0
    var total = 0
}
