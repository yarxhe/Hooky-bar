import Foundation

/// Единый интерфейс для приложений заметок. Будущие SDK-интеграции подключаются здесь.
protocol NotesAppAdapter {
    var app: NotesApp { get }
    var isInstalled: Bool { get }
    var capability: IntegrationCapabilityDeclaration { get }

    func openNotes() -> IntegrationResult
    func createNote() -> IntegrationResult
}

final class NotesAdapterRegistry {
    private var adapters: [NotesApp: any NotesAppAdapter] = [:]

    init(adapters: [any NotesAppAdapter] = []) {
        adapters.forEach(register)
    }

    static func builtIn() -> NotesAdapterRegistry {
        NotesAdapterRegistry(adapters: [AppleNotesAdapter(), ObsidianNotesAdapter()])
    }

    func register(_ adapter: any NotesAppAdapter) {
        adapters[adapter.app] = adapter
    }

    func adapter(for app: NotesApp) -> (any NotesAppAdapter)? {
        adapters[app]
    }

    var registeredApps: [NotesApp] {
        NotesApp.allCases.filter { adapters[$0] != nil }
    }

    var integrationCapabilities: [IntegrationCapabilityDeclaration] {
        registeredApps
            .compactMap { adapters[$0]?.capability }
            .sorted { $0.id < $1.id }
    }
}
