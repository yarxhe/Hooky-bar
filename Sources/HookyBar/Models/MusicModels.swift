import AppKit
import SwiftUI

struct NowPlayingSnapshot {
    var title = L10n.tr("music.nothingPlaying")
    var artist = L10n.tr("music.yandex.full")
    var duration: Double = 0
    var elapsed: Double = 0
    var isPlaying = false
    var isLiked = false
    var isDisliked = false
    var artwork: NSImage?
}

enum MusicSource: String, CaseIterable, Identifiable {
    case yandex
    case appleMusic
    case spotify

    var id: String { rawValue }

    var title: String {
        switch self {
        case .yandex: return L10n.tr("music.yandex.short")
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }

    var fullTitle: String {
        switch self {
        case .yandex: return L10n.tr("music.yandex.full")
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .yandex: return "ru.yandex.desktop.music"
        case .appleMusic: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        }
    }

    var fallbackSymbol: String {
        switch self {
        case .yandex: return "sun.max.fill"
        case .appleMusic: return "music.note"
        case .spotify: return "dot.radiowaves.left.and.right"
        }
    }

    var tint: Color {
        switch self {
        case .yandex: return .yellow
        case .appleMusic: return .pink
        case .spotify: return .green
        }
    }
}

struct UpcomingTrack: Equatable, Decodable {
    let title: String
    let artist: String
}
