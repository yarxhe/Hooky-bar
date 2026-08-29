import Foundation

enum ToolAction: String, Hashable {
    case openCalendar
    case openDownloads
    case copyWorkspacePath
    case openWorkspaceInIDE
    case openWorkspaceInTerminal
    case openWorkspaceInFinder
    case openDeveloperRepository
    case openDeveloperActivity
    case openDeveloperIssues
    case openDeveloperRelease
    case openDeveloperDiscussion
}

enum DeveloperIDE: String, CaseIterable, Identifiable {
    case visualStudioCode
    case cursor
    case zed
    case xcode
    case intellijIdea
    case webStorm
    case pyCharm
    case clion
    case goLand
    case rider
    case rustRover
    case dataGrip

    var id: String { rawValue }

    static let editors: [DeveloperIDE] = [
        .visualStudioCode,
        .cursor,
        .zed,
        .xcode
    ]

    static let jetBrainsIDEs: [DeveloperIDE] = [
        .intellijIdea,
        .webStorm,
        .pyCharm,
        .clion,
        .goLand,
        .rider,
        .rustRover,
        .dataGrip
    ]

    var title: String {
        switch self {
        case .visualStudioCode: return "VS Code"
        case .cursor: return "Cursor"
        case .zed: return "Zed"
        case .xcode: return "Xcode"
        case .intellijIdea: return "IntelliJ IDEA"
        case .webStorm: return "WebStorm"
        case .pyCharm: return "PyCharm"
        case .clion: return "CLion"
        case .goLand: return "GoLand"
        case .rider: return "Rider"
        case .rustRover: return "RustRover"
        case .dataGrip: return "DataGrip"
        }
    }

    /// Некоторые IDE имеют отдельные bundle ID для платной и Community-версии.
    var bundleIdentifiers: [String] {
        switch self {
        case .visualStudioCode: return ["com.microsoft.VSCode"]
        case .cursor: return ["com.todesktop.230313mzl4w4u92"]
        case .zed: return ["dev.zed.Zed"]
        case .xcode: return ["com.apple.dt.Xcode"]
        case .intellijIdea: return ["com.jetbrains.intellij", "com.jetbrains.intellij.ce"]
        case .webStorm: return ["com.jetbrains.WebStorm"]
        case .pyCharm: return ["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"]
        case .clion: return ["com.jetbrains.CLion"]
        case .goLand: return ["com.jetbrains.goland"]
        case .rider: return ["com.jetbrains.rider"]
        case .rustRover: return ["com.jetbrains.rustrover"]
        case .dataGrip: return ["com.jetbrains.datagrip"]
        }
    }

    var symbol: String {
        switch self {
        case .visualStudioCode: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursorarrow.rays"
        case .zed: return "bolt.fill"
        case .xcode: return "hammer.fill"
        case .intellijIdea, .webStorm, .pyCharm, .clion,
             .goLand, .rider, .rustRover, .dataGrip:
            return "square.stack.3d.up.fill"
        }
    }
}

struct DeveloperWorkspaceSnapshot: Equatable {
    var folderName = L10n.tr("dev.projectNotSelected")
    var path = ""
    var branch = "—"
    var changedFiles = 0
    var untrackedFiles = 0
    var ahead = 0
    var behind = 0
    var stashCount = 0
    var lastCommit = ""

    var isConfigured: Bool { !path.isEmpty }
}

enum DeveloperActivityKind: Equatable {
    case workflow
    case pullRequest
}

enum DeveloperCIState: Equatable {
    case notConfigured
    case unavailable
    case noRuns
    case queued
    case running
    case success
    case failure
    case cancelled
}

struct DeveloperCISnapshot: Equatable {
    var repository = ""
    var kind: DeveloperActivityKind = .workflow
    var workflow = "GitHub Actions"
    var title = L10n.tr("dev.ci.addOrigin")
    var branch = ""
    var status = L10n.tr("dev.ci.placeholder")
    var state: DeveloperCIState = .notConfigured
    var repositoryURL: URL?
    var runURL: URL?

    var hasRepository: Bool { repositoryURL != nil }
    var canOpenRun: Bool { runURL != nil }
}

enum DeveloperCommandKind: String, CaseIterable, Equatable {
    case run
    case test
    case build
}

enum DeveloperCommandRunState: Equatable {
    case idle
    case running
    case success
    case failure(Int32)
    case cancelled
}

struct DeveloperCommandSnapshot: Equatable {
    var toolchain = ""
    var availableCommands: Set<DeveloperCommandKind> = []
    var lastCommand: DeveloperCommandKind?
    var state: DeveloperCommandRunState = .idle
    var output = ""

    func isAvailable(_ command: DeveloperCommandKind) -> Bool {
        availableCommands.contains(command)
    }
}

struct DeveloperGitHubActivityItem: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case issue
        case release
        case discussion
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let url: URL

    var id: String { "\(kind.rawValue):\(url.absoluteString)" }
}

struct DeveloperGitHubActivitySnapshot: Equatable {
    var issues: [DeveloperGitHubActivityItem] = []
    var latestRelease: DeveloperGitHubActivityItem?
    var pullRequestDiscussion: DeveloperGitHubActivityItem?

    var openIssueCount: Int { issues.count }
    var latestIssue: DeveloperGitHubActivityItem? { issues.first }
}
