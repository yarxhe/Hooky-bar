import Combine
import Foundation

final class NotesStore: ObservableObject {
    @Published private(set) var selectedApp: NotesApp
    @Published private(set) var status: String?

    private let defaults: UserDefaults
    private let registry: NotesAdapterRegistry
    private let selectionKey = "notes.selectedApp"

    init(defaults: UserDefaults = .standard, registry: NotesAdapterRegistry = .builtIn()) {
        self.defaults = defaults
        self.registry = registry
        if let saved = defaults.string(forKey: selectionKey).flatMap(NotesApp.init(rawValue:)) {
            selectedApp = saved
        } else {
            // Сохраняем прежнее поведение для существующих пользователей Obsidian,
            // а на чистой установке используем системные «Заметки».
            selectedApp = registry.adapter(for: .obsidian)?.isInstalled == true
                ? .obsidian : .appleNotes
        }
    }

    func select(_ app: NotesApp) {
        selectedApp = app
        defaults.set(app.rawValue, forKey: selectionKey)
        status = nil
    }

    func isInstalled(_ app: NotesApp) -> Bool {
        registry.adapter(for: app)?.isInstalled == true
    }

    func openNotes() {
        perform(action: { $0.openNotes() })
    }

    func createNote() {
        perform(action: { $0.createNote() })
    }

    func register(_ adapter: any NotesAppAdapter) {
        registry.register(adapter)
    }

    private func perform(action: (any NotesAppAdapter) -> IntegrationResult) {
        guard let adapter = registry.adapter(for: selectedApp), adapter.isInstalled else {
            status = L10n.tr("notes.notInstalled.format", selectedApp.title)
            return
        }
        status = action(adapter).succeeded ? nil : L10n.tr("notes.openFailed.format", selectedApp.title)
    }

    func refreshLocalizedContent() { status = nil }
}
