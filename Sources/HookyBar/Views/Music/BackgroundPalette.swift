import AppKit
import SwiftUI

/// Постоянные три RGB-слота позволяют SwiftUI интерполировать именно цвета Canvas,
/// сохраняя его identity, геометрию и фазу TimelineView при переключении трека.
struct BackgroundPalette: VectorArithmetic {
    private var components: [Double]

    init(colors: [Color]) {
        let source = colors.isEmpty ? ArtworkPalette.fallback : colors
        components = (0..<3).flatMap { index -> [Double] in
            let color = NSColor(source[index % source.count]).usingColorSpace(.sRGB) ?? .black
            return [Double(color.redComponent), Double(color.greenComponent), Double(color.blueComponent)]
        }
    }

    private init(components: [Double]) { self.components = components }

    static let zero = BackgroundPalette(components: Array(repeating: 0, count: 9))

    static func + (lhs: Self, rhs: Self) -> Self {
        Self(components: zip(lhs.components, rhs.components).map { $0 + $1 })
    }

    static func - (lhs: Self, rhs: Self) -> Self {
        Self(components: zip(lhs.components, rhs.components).map { $0 - $1 })
    }

    mutating func scale(by rhs: Double) { components = components.map { $0 * rhs } }
    var magnitudeSquared: Double { components.reduce(0) { $0 + $1 * $1 } }

    var colors: [Color] {
        (0..<3).map { index in
            let offset = index * 3
            return Color(.sRGB, red: components[offset], green: components[offset + 1],
                         blue: components[offset + 2], opacity: 1)
        }
    }
}
