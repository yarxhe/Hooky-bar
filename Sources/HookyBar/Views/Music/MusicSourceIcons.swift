import SwiftUI

struct MusicSourceIcon: View {
    let source: MusicSource

    var body: some View {
        HookyBrandIcon(asset: brandAsset, fallbackSymbol: source.fallbackSymbol)
    }

    private var brandAsset: HookyBrandAsset {
        switch source {
        case .yandex: .yandexMusic
        case .appleMusic: .appleMusic
        case .spotify: .spotify
        }
    }
}
