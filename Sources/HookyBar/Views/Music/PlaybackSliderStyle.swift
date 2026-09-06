import SwiftUI

/// Общий спокойный цвет ползунков, независимый от обложки трека.
enum PlaybackSliderStyle {
    static let fill = Color(red: 0.66, green: 0.62, blue: 0.78)
    static let track = Color.white.opacity(0.10)
    static let thumb = Color(white: 0.92)
    static let thickness: CGFloat = 8
}
