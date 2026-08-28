import AppKit
import SwiftUI

/// Кастомные логотипы Hooky bar и поддерживаемых приложений.
enum HookyBrandAsset: String, CaseIterable {
    case hookyBar = "hookybar_logo"
    case yandexMusic = "yandex_music_logo"
    case appleMusic = "apple_music_logo"
    case spotify = "spotify_logo"
    case appleNotes = "apple_notes_logo"
    case obsidian = "obsidian_logo"

    var accessibilityLabel: String {
        switch self {
        case .hookyBar: "Hooky bar"
        case .yandexMusic: L10n.tr("music.yandex.full")
        case .appleMusic: "Apple Music"
        case .spotify: "Spotify"
        case .appleNotes: L10n.tr("notes.apple.title")
        case .obsidian: "Obsidian"
        }
    }
}

/// Загружает PNG один раз и переиспользует NSImage во всех SwiftUI-экранах.
enum HookyBrandImages {
    private static let images: [HookyBrandAsset: NSImage] = Dictionary(
        uniqueKeysWithValues: HookyBrandAsset.allCases.compactMap { asset in
            let url = Bundle.module.url(
                forResource: asset.rawValue,
                withExtension: "png",
                subdirectory: "BrandIcons"
            ) ?? Bundle.module.url(forResource: asset.rawValue, withExtension: "png")
            guard let url, let image = NSImage(contentsOf: url) else { return nil }
            return (asset, image)
        }
    )

    static func image(for asset: HookyBrandAsset) -> NSImage? {
        images[asset]
    }
}

struct HookyBrandIcon: View {
    let asset: HookyBrandAsset
    var fallbackSymbol = "app.fill"

    var body: some View {
        Group {
            if let image = HookyBrandImages.image(for: asset) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: fallbackSymbol)
                    .resizable()
                    .scaledToFit()
                    .padding(3)
            }
        }
        .accessibilityLabel(asset.accessibilityLabel)
    }
}
