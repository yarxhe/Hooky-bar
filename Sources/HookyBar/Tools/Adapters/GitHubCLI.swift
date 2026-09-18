import Foundation
import Darwin

private final class BoundedProcessOutput: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let limit: Int

    init(limit: Int = 2 * 1_024 * 1_024) {
        self.limit = limit
    }

    func append(_ incoming: Data) {
        guard !incoming.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, limit - data.count)
        if remaining > 0 { data.append(incoming.prefix(remaining)) }
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

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
        acceptedExitCodes: Set<Int32> = [0],
        timeout: TimeInterval = 8
    ) -> String? {
        let process = Process()
        let output = Pipe()
        let collectedOutput = BoundedProcessOutput()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { handle in
            collectedOutput.append(handle.availableData)
        }
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return nil }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 0.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 0.5)
            }
            output.fileHandleForReading.readabilityHandler = nil
            collectedOutput.append(output.fileHandleForReading.readDataToEndOfFile())
            return nil
        }
        output.fileHandleForReading.readabilityHandler = nil
        collectedOutput.append(output.fileHandleForReading.readDataToEndOfFile())
        let data = collectedOutput.snapshot()
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
