import SwiftUI

enum HookyTheme {
    /// Постоянный акцент интерактивных элементов. Он не зависит от обложки трека.
    static let controlAccent = Color(red: 0.48, green: 0.42, blue: 1.0)

    /// Neutral dark material; no colored glass tint or reflective outline.
    static let materialShade = Color.black.opacity(0.18)
    static let materialOpaqueFill = Color(white: 0.14)
}
