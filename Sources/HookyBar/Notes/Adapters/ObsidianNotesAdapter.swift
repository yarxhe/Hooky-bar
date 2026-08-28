import AppKit

struct ObsidianNotesAdapter: NotesAppAdapter {
    let app: NotesApp = .obsidian
    let capability = IntegrationCapabilityDeclaration(id: "notes.obsidian")

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "md.obsidian") != nil
    }

    func openNotes() -> IntegrationResult {
        guard let applicationURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "md.obsidian") else {
            return .failed(.notInstalled)
        }
        return NSWorkspace.shared.open(applicationURL) ? .success : .failed(.commandRejected)
    }

    func createNote() -> IntegrationResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let name = L10n.tr("notes.newFile.format", formatter.string(from: Date()))
        return open(file: "Hooky bar/\(name)")
    }

    private func open(file: String) -> IntegrationResult {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "new"
        components.queryItems = [URLQueryItem(name: "file", value: file)]
        guard let url = components.url else { return .failed(.invalidConfiguration) }
        return NSWorkspace.shared.open(url) ? .success : .failed(.commandRejected)
    }
}
