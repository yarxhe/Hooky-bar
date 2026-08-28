import Foundation

enum NotesApp: String, CaseIterable, Identifiable {
    case appleNotes
    case obsidian

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleNotes: L10n.tr("notes.apple.title")
        case .obsidian: "Obsidian"
        }
    }

    var subtitle: String {
        switch self {
        case .appleNotes: L10n.tr("notes.apple.subtitle")
        case .obsidian: L10n.tr("notes.obsidian.subtitle")
        }
    }

    var symbol: String {
        switch self {
        case .appleNotes: "note.text"
        case .obsidian: "diamond.fill"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .appleNotes: "com.apple.Notes"
        case .obsidian: "md.obsidian"
        }
    }
}
