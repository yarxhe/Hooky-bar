import Foundation

enum ClipboardItemKind: String, CaseIterable {
    case text
    case screenshot
}

/// Единая модель элемента буфера. Новые SDK-источники должны отдавать эту же модель.
struct ClipboardItem: Identifiable, Equatable {
    let id: String
    let sourceID: String
    let sourceName: String
    let sourceBundleIdentifier: String?
    let kind: ClipboardItemKind
    let text: String?
    let fileURL: URL?
    let createdAt: Date

    var searchableText: String {
        [text, fileURL?.lastPathComponent, sourceName]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    var isLink: Bool {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: text), let scheme = url.scheme?.lowercased()
        else { return false }
        return scheme == "http" || scheme == "https"
    }

    var isProbablyCode: Bool {
        guard let text else { return false }
        let markers = ["func ", "let ", "const ", "class ", "struct ", "import ", "=>", "{\n", "</"]
        return text.contains("\n") && markers.contains(where: text.contains)
    }
}
