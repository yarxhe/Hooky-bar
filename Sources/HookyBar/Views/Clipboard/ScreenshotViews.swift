import Cocoa
import ImageIO
import SwiftUI

final class ThumbnailLoader: ObservableObject {
    fileprivate static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 12
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()
    @Published var image: NSImage?
    private let url: URL
    private let size: CGSize
    private let cacheKey: NSString

    init(url: URL, size: CGSize) {
        self.url = url
        self.size = size
        self.cacheKey = "\(url.path)|\(Int(size.width))x\(Int(size.height))" as NSString
        self.image = Self.cache.object(forKey: cacheKey)
        if image == nil {
            DispatchQueue.main.async { [weak self] in self?.load() }
        }
    }

    fileprivate static func immediateThumbnail(url: URL, size: CGSize) -> NSImage? {
        let key = "\(url.path)|\(Int(size.width))x\(Int(size.height))" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height) * scale,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        store(image, forKey: key)
        return image
    }

    static func trimCache() {
        cache.removeAllObjects()
    }

    private static func store(_ image: NSImage, forKey key: NSString) {
        let cost = image.representations.first.map { max(1, $0.pixelsWide * $0.pixelsHigh * 4) } ?? 1
        cache.setObject(image, forKey: key, cost: cost)
    }

    func load(attempt: Int = 0) {
        guard image == nil else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let url = self.url
        let maxPixelSize = max(size.width, size.height) * scale
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceShouldCacheImmediately: true
            ]
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)
            let cgImage = source.flatMap { CGImageSourceCreateThumbnailAtIndex($0, 0, options as CFDictionary) }
            let decoded = cgImage.map { NSImage(cgImage: $0, size: .zero) }
            DispatchQueue.main.async {
                guard let self else { return }
                if let decoded {
                    self.image = decoded
                    Self.store(decoded, forKey: self.cacheKey)
                } else if attempt < 7 {
                    let delay = min(0.65, 0.10 + Double(attempt) * 0.09)
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.load(attempt: attempt + 1)
                    }
                }
            }
        }
    }
}

struct AsyncThumbnail: View {
    let contentMode: ContentMode
    @StateObject private var loader: ThumbnailLoader

    init(url: URL, size: CGSize, contentMode: ContentMode) {
        self.contentMode = contentMode
        _loader = StateObject(wrappedValue: ThumbnailLoader(url: url, size: size))
    }

    var body: some View {
        Group {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    Color.white.opacity(0.045)
                    ProgressView().controlSize(.small).tint(.white.opacity(0.5))
                }
            }
        }
    }
}

struct ScreenshotCapturePane: View {
    let url: URL
    let copy: () -> Void

    var body: some View {
        VStack(spacing: 11) {
            Group {
                if let image = ThumbnailLoader.immediateThumbnail(
                    url: url,
                    size: CGSize(width: 700, height: 330)
                ) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                } else {
                    ZStack {
                        Color.white.opacity(0.045)
                        ProgressView().controlSize(.small).tint(.white.opacity(0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(0.12)))

            Button(action: copy) {
                Label(L10n.tr("clipboard.copy"), systemImage: "doc.on.doc")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .foregroundStyle(Color.black)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 15)
    }
}
