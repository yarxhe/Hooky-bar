import SwiftUI

enum HookyTheme {
    /// Постоянный акцент интерактивных элементов. Он не зависит от обложки трека.
    static let controlAccent = Color(red: 0.48, green: 0.42, blue: 1.0)

    /// Все стеклянные поверхности используют один tint и один уровень материала.
    static let glassTint = controlAccent.opacity(0.13)
    static let glassFallbackFill = Color.primary.opacity(0.065)
    static let glassFallbackStroke = Color.primary.opacity(0.11)
}
