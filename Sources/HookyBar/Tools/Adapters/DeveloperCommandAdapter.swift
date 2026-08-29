import Foundation

/// Запускает только явно нажатые пользователем команды обнаруженного toolchain.
/// Команды из файлов репозитория автоматически не исполняются.
final class DeveloperCommandAdapter {
    let capability = IntegrationCapabilityDeclaration(id: "utilities.developer.commands")

    private var activeProcess: Process?
    private var activeLogURL: URL?
    private var cancelRequested = false

    func inspectWorkspace(at workspaceURL: URL) -> DeveloperCommandSnapshot {
        guard let profile = Self.profile(at: workspaceURL) else { return DeveloperCommandSnapshot() }
        return DeveloperCommandSnapshot(
            toolchain: profile.name,
            availableCommands: Set(profile.commands.keys)
        )
    }

    @discardableResult
    func run(
        _ command: DeveloperCommandKind,
        at workspaceURL: URL,
        completion: @escaping (DeveloperCommandRunState, String) -> Void
    ) -> Bool {
        guard activeProcess == nil,
              let specification = Self.profile(at: workspaceURL)?.commands[command] else { return false }

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("hooky-dev-command-\(UUID().uuidString).log")
        guard FileManager.default.createFile(atPath: logURL.path, contents: nil),
              let log = try? FileHandle(forWritingTo: logURL) else { return false }

        let process = Process()
        process.executableURL = specification.executable
        process.arguments = specification.arguments
        process.currentDirectoryURL = workspaceURL
        process.standardOutput = log
        process.standardError = log
        process.environment = Self.commandEnvironment
        process.terminationHandler = { [weak self, weak process] finished in
            try? log.close()
            let output = Self.outputTail(at: logURL)
            try? FileManager.default.removeItem(at: logURL)
            DispatchQueue.main.async {
                guard let self, self.activeProcess === process else { return }
                self.activeProcess = nil
                self.activeLogURL = nil
                let state: DeveloperCommandRunState
                if self.cancelRequested {
                    state = .cancelled
                } else {
                    state = finished.terminationStatus == 0
                        ? .success : .failure(finished.terminationStatus)
                }
                self.cancelRequested = false
                completion(state, output)
            }
        }

        do {
            try process.run()
            cancelRequested = false
            activeProcess = process
            activeLogURL = logURL
            return true
        } catch {
            try? log.close()
            try? FileManager.default.removeItem(at: logURL)
            return false
        }
    }

    func cancel() {
        cancelRequested = true
        activeProcess?.terminate()
    }

    func stop() {
        activeProcess?.terminate()
        activeProcess = nil
        cancelRequested = false
        if let activeLogURL { try? FileManager.default.removeItem(at: activeLogURL) }
        activeLogURL = nil
    }

    static func detectedToolchain(at workspaceURL: URL) -> String? {
        profile(at: workspaceURL)?.name
    }

    private static func profile(at workspaceURL: URL) -> CommandProfile? {
        let manager = FileManager.default
        func contains(_ name: String) -> Bool {
            manager.fileExists(atPath: workspaceURL.appendingPathComponent(name).path)
        }

        if contains("Package.swift"), let swift = executable(named: "swift") {
            return CommandProfile(name: "Swift", commands: [
                .run: CommandSpecification(executable: swift, arguments: ["run"]),
                .test: CommandSpecification(executable: swift, arguments: ["test"]),
                .build: CommandSpecification(executable: swift, arguments: ["build", "-c", "release"])
            ])
        }

        if contains("package.json"), let npm = executable(named: "npm"),
           let data = try? Data(contentsOf: workspaceURL.appendingPathComponent("package.json")),
           let package = try? JSONDecoder().decode(NodePackage.self, from: data) {
            var commands: [DeveloperCommandKind: CommandSpecification] = [:]
            if package.scripts["dev"] != nil {
                commands[.run] = CommandSpecification(executable: npm, arguments: ["run", "dev"])
            } else if package.scripts["start"] != nil {
                commands[.run] = CommandSpecification(executable: npm, arguments: ["run", "start"])
            }
            if package.scripts["test"] != nil {
                commands[.test] = CommandSpecification(executable: npm, arguments: ["test"])
            }
            if package.scripts["build"] != nil {
                commands[.build] = CommandSpecification(executable: npm, arguments: ["run", "build"])
            }
            return commands.isEmpty ? nil : CommandProfile(name: "Node.js", commands: commands)
        }

        if contains("go.mod"), let go = executable(named: "go") {
            return CommandProfile(name: "Go", commands: [
                .run: CommandSpecification(executable: go, arguments: ["run", "."]),
                .test: CommandSpecification(executable: go, arguments: ["test", "./..."]),
                .build: CommandSpecification(executable: go, arguments: ["build", "./..."])
            ])
        }

        if contains("Cargo.toml"), let cargo = executable(named: "cargo") {
            return CommandProfile(name: "Rust", commands: [
                .run: CommandSpecification(executable: cargo, arguments: ["run"]),
                .test: CommandSpecification(executable: cargo, arguments: ["test"]),
                .build: CommandSpecification(executable: cargo, arguments: ["build", "--release"])
            ])
        }
        return nil
    }

    private static func executable(named name: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)",
            "\(home)/.cargo/bin/\(name)",
            "\(home)/go/bin/\(name)"
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:))
            .map(URL.init(fileURLWithPath:))
    }

    private static var commandEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        environment["PATH"] = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
            "\(home)/.cargo/bin", "\(home)/go/bin"
        ].joined(separator: ":")
        environment["NO_COLOR"] = "1"
        environment["CLICOLOR"] = "0"
        environment["TERM"] = "dumb"
        return environment
    }

    private static func outputTail(at url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        let tail = data.suffix(12_000)
        return String(decoding: tail, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct CommandProfile {
    let name: String
    let commands: [DeveloperCommandKind: CommandSpecification]
}

private struct CommandSpecification {
    let executable: URL
    let arguments: [String]
}

private struct NodePackage: Decodable {
    let scripts: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scripts = try container.decodeIfPresent([String: String].self, forKey: .scripts) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case scripts
    }
}
