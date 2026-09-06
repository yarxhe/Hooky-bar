import AppKit
import SwiftUI

enum ArtworkPalette {
    static let fallback: [Color] = [.indigo, .purple, .blue]

    /// MediaRemote sometimes returns the original multi-megapixel cover.
    /// The island never renders it large, so keep a compact decoded bitmap.
    static func displayArtwork(from image: NSImage?, maxPixelSize: Int = 256) -> NSImage? {
        guard let image,
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              source.width > 0, source.height > 0 else { return image }
        let longestSide = max(source.width, source.height)
        // Keep a 2× backing bitmap for Retina without retaining the original
        // multi-megapixel representation delivered by some players.
        let targetPixelSize = maxPixelSize * 2
        guard longestSide > targetPixelSize else { return image }
        let scale = CGFloat(targetPixelSize) / CGFloat(longestSide)
        let width = max(1, Int((CGFloat(source.width) * scale).rounded()))
        let height = max(1, Int((CGFloat(source.height) * scale).rounded()))
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return image }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage() else { return image }
        return NSImage(cgImage: result, size: NSSize(width: width, height: height))
    }

    private struct Bucket {
        var count = 0
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0

        mutating func add(_ color: NSColor) {
            count += 1
            red += color.redComponent
            green += color.greenComponent
            blue += color.blueComponent
        }

        var color: NSColor {
            let divisor = CGFloat(max(1, count))
            return NSColor(srgbRed: red / divisor, green: green / divisor, blue: blue / divisor, alpha: 1)
        }
    }

    static func colors(from image: NSImage) -> [Color] {
        // Фиксированный объём работы даже для больших обложек, без TIFF-копии оригинала.
        let side = 32
        guard image.size.width > 0, image.size.height > 0,
              let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: side * 4, bitsPerPixel: 32
              ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return fallback }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side),
                   from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        var buckets = Array(repeating: Bucket(), count: 18)
        var neutral = Bucket()
        var visibleCount = 0
        for y in 0..<side {
            for x in 0..<side {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.5 else { continue }
                visibleCount += 1
                neutral.add(color)
                guard color.saturationComponent > 0.16, color.brightnessComponent > 0.08 else { continue }
                let index = min(17, Int(color.hueComponent * 18))
                buckets[index].add(color)
            }
        }
        guard visibleCount > 0 else { return fallback }

        // Площадь цвета важнее насыщенности одного пикселя/логотипа.
        let minimumCount = max(3, visibleCount / 64)
        let candidates = buckets.enumerated()
            .filter { $0.element.count >= minimumCount }
            .sorted { left, right in
                let a = CGFloat(left.element.count) * (0.7 + left.element.color.saturationComponent * 0.3)
                let b = CGFloat(right.element.count) * (0.7 + right.element.color.saturationComponent * 0.3)
                return a == b ? left.offset < right.offset : a > b
            }
        var selected: [NSColor] = []
        for candidate in candidates {
            let color = candidate.element.color
            let different = selected.allSatisfy {
                let distance = abs($0.hueComponent - color.hueComponent)
                return min(distance, 1 - distance) > 0.09
            }
            if different { selected.append(color) }
            if selected.count == 3 { break }
        }
        if selected.isEmpty {
            // Чёрно-белые обложки дают нейтральный свет, а не случайный жёлтый фон.
            let brightness = min(0.8, max(0.32, neutral.color.brightnessComponent))
            return [0.7, 1.0, 0.85].map { Color(white: brightness * $0) }
        }
        return selected.map { Color(nsColor: $0) }
    }
}
