import SwiftUI

/// Показывает кастомный логотип выбранного приложения заметок.
struct NotesAppIcon: View {
    let app: NotesApp

    var body: some View {
        HookyBrandIcon(asset: brandAsset, fallbackSymbol: app.symbol)
    }

    private var brandAsset: HookyBrandAsset {
        switch app {
        case .appleNotes: .appleNotes
        case .obsidian: .obsidian
        }
    }
}
