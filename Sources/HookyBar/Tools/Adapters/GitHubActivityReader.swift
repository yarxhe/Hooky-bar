import Foundation

/// Читает Issues, последний Release и обсуждение PR отдельно от CI-статуса.
enum GitHubActivityReader {
    static func read(at workspaceURL: URL) -> DeveloperGitHubActivitySnapshot {
        guard let context = GitHubCLI.context(at: workspaceURL),
              let gh = context.ghExecutable else { return DeveloperGitHubActivitySnapshot() }
        return DeveloperGitHubActivitySnapshot(
            issues: openIssues(context: context, gh: gh),
            latestRelease: latestRelease(context: context, gh: gh),
            pullRequestDiscussion: pullRequestDiscussion(context: context, gh: gh)
        )
    }

    private static func openIssues(
        context: GitHubRepositoryContext,
        gh: String
    ) -> [DeveloperGitHubActivityItem] {
        guard let output = GitHubCLI.run(
            executable: gh,
            arguments: [
                "issue", "list", "--repo", context.repository, "--state", "open", "--limit", "100",
                "--json", "number,title,url,comments"
            ]
        ), let data = output.data(using: .utf8),
              let issues = try? JSONDecoder().decode([GitHubIssue].self, from: data) else { return [] }
        return issues.compactMap { issue in
            guard let url = URL(string: issue.url) else { return nil }
            return DeveloperGitHubActivityItem(
                kind: .issue,
                title: "#\(issue.number) \(issue.title)",
                subtitle: L10n.tr("dev.github.issueComments.format", issue.comments.count),
                url: url
            )
        }
    }

    private static func latestRelease(
        context: GitHubRepositoryContext,
        gh: String
    ) -> DeveloperGitHubActivityItem? {
        guard let output = GitHubCLI.run(
            executable: gh,
            arguments: [
                "release", "view", "--repo", context.repository,
                "--json", "name,tagName,url,isPrerelease"
            ]
        ), let data = output.data(using: .utf8),
              let release = try? JSONDecoder().decode(GitHubRelease.self, from: data),
              let url = URL(string: release.url) else { return nil }
        return DeveloperGitHubActivityItem(
            kind: .release,
            title: release.name.nilIfEmpty ?? release.tagName,
            subtitle: release.isPrerelease
                ? L10n.tr("dev.github.prerelease.format", release.tagName)
                : L10n.tr("dev.github.release.format", release.tagName),
            url: url
        )
    }

    private static func pullRequestDiscussion(
        context: GitHubRepositoryContext,
        gh: String
    ) -> DeveloperGitHubActivityItem? {
        guard !context.branch.isEmpty, let output = GitHubCLI.run(
            executable: gh,
            arguments: [
                "pr", "view", context.branch, "--repo", context.repository,
                "--json", "number,title,url,comments,latestReviews"
            ]
        ), let data = output.data(using: .utf8),
              let discussion = try? JSONDecoder().decode(PullRequestDiscussion.self, from: data),
              let url = URL(string: discussion.url) else { return nil }

        let latestEntry = discussion.comments.last ?? discussion.latestReviews.last
        let preview = latestEntry.map(commentPreview) ?? L10n.tr("dev.github.noComments")
        return DeveloperGitHubActivityItem(
            kind: .discussion,
            title: L10n.tr(
                "dev.github.discussion.format",
                discussion.number,
                discussion.comments.count,
                discussion.latestReviews.count
            ),
            subtitle: preview,
            url: url
        )
    }

    private static func commentPreview(_ comment: GitHubComment) -> String {
        let body = comment.body
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let shortened = body.count > 96 ? "\(body.prefix(93))…" : body
        guard let login = comment.author?.login.nilIfEmpty else { return shortened }
        return shortened.isEmpty ? "@\(login)" : "@\(login): \(shortened)"
    }
}

private struct GitHubIssue: Decodable {
    let number: Int
    let title: String
    let url: String
    let comments: [GitHubComment]
}

private struct GitHubRelease: Decodable {
    let name: String
    let tagName: String
    let url: String
    let isPrerelease: Bool
}

private struct PullRequestDiscussion: Decodable {
    let number: Int
    let url: String
    let comments: [GitHubComment]
    let latestReviews: [GitHubComment]
}

private struct GitHubComment: Decodable {
    let author: GitHubAuthor?
    let body: String
}

private struct GitHubAuthor: Decodable {
    let login: String
}
