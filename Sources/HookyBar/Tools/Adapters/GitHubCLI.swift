import Foundation

struct GitHubRepositoryContext {
    let repository: String
    let repositoryURL: URL
    let branch: String
    let ghExecutable: String?
}

/// Общая безопасная обвязка `git`/`gh`: аргументы передаются напрямую без shell-интерполяции.
enum GitHubCLI {
    static func context(at workspaceURL: URL) -> GitHubRepositoryContext? {
        guard let remote = run(
            executable: "/usr/bin/git",
            arguments: ["-C", workspaceURL.path, "remote", "get-url", "origin"]
        ), let repository = repositorySlug(from: remote),
              let repositoryURL = URL(string: "https://github.com/\(repository)") else { return nil }
        let branch = run(
            executable: "/usr/bin/git",
            arguments: ["-C", workspaceURL.path, "branch", "--show-current"]
        ) ?? ""
        return GitHubRepositoryContext(
            repository: repository,
            repositoryURL: repositoryURL,
            branch: branch,
            ghExecutable: ghExecutable
        )
    }

    static func run(
        executable: String,
        arguments: [String],
        acceptedExitCodes: Set<Int32> = [0]
    ) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard acceptedExitCodes.contains(process.terminationStatus) else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func repositorySlug(from remote: String) -> String? {
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

    private static var ghExecutable: String? {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
