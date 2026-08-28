import AppKit

struct AppleNotesAdapter: NotesAppAdapter {
    let app: NotesApp = .appleNotes
    var isInstalled: Bool { true }
    let capability = IntegrationCapabilityDeclaration(
        id: "notes.apple",
        permissions: [.automation]
    )

    func openNotes() -> IntegrationResult {
        guard let url = URL(string: "notes://") else { return .failed(.invalidConfiguration) }
        return NSWorkspace.shared.open(url) ? .success : .failed(.commandRejected)
    }

    func createNote() -> IntegrationResult {
        let script = NSAppleScript(source: """
            tell application id "com.apple.Notes"
                activate
                tell default account
                    set createdNote to make new note with properties {body:""}
                end tell
                show createdNote
            end tell
            """)
        var error: NSDictionary?
        script?.executeAndReturnError(&error)
        return error == nil ? .success : .failed(.permissionDenied(.automation))
    }
}
