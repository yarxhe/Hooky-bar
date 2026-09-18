import AppKit
import SwiftUI

/// Ограничивает ближайший ScrollView, не перехватывая события колеса.
struct VerticalScrollLock: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.attach(from: view) }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { context.coordinator.attach(from: view) }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.detach() }

    final class Coordinator {
        private weak var scroll: NSScrollView?
        private var observer: NSObjectProtocol?
        private var correctingOrigin = false
        private var lockedOriginX: CGFloat?
        func attach(from view: NSView) {
            guard let parent = view.enclosingScrollView else { return }
            if scroll !== parent {
                detach()
                scroll = parent
                parent.contentView.postsBoundsChangedNotifications = true
                observer = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: parent.contentView, queue: .main
                ) { [weak self] _ in self?.lockAxis() }
            }
            // Configure on attachment/update, not for every scrolling frame.
            if parent.hasHorizontalScroller { parent.hasHorizontalScroller = false }
            if parent.horizontalScrollElasticity != .none { parent.horizontalScrollElasticity = .none }
            if !parent.usesPredominantAxisScrolling { parent.usesPredominantAxisScrolling = true }
            updateLockedAxis()
        }
        private func lockAxis() {
            guard !correctingOrigin, let scroll else { return }
            let clip = scroll.contentView
            let tolerance = 0.5 / (clip.window?.backingScaleFactor ?? 2)
            // A vertical scroll emits a bounds notification for every frame.
            // The horizontal origin is normally already stable, so avoid an
            // AppKit constrain/layout pass unless it has actually drifted.
            if let lockedOriginX, abs(clip.bounds.origin.x - lockedOriginX) <= tolerance {
                return
            }
            updateLockedAxis()
        }
        private func updateLockedAxis() {
            guard !correctingOrigin, let scroll else { return }
            let clip = scroll.contentView
            var proposed = clip.bounds
            proposed.origin = Self.verticalOrigin(proposed.origin)
            // SwiftUI's clip view may have an inset/nonzero legal origin. Asking
            // it to scroll to literal zero on each notification fights AppKit
            // and recursively triggers a second SwiftUI layout/scroll update.
            let nativeX = clip.constrainBoundsRect(proposed).origin.x
            let tolerance = 0.5 / (clip.window?.backingScaleFactor ?? 2)
            lockedOriginX = nativeX
            guard abs(clip.bounds.origin.x - nativeX) > tolerance else { return }
            correctingOrigin = true
            defer { correctingOrigin = false }
            clip.scroll(to: NSPoint(x: nativeX, y: clip.bounds.origin.y))
            scroll.reflectScrolledClipView(clip)
        }
        static func verticalOrigin(_ point: NSPoint) -> NSPoint { NSPoint(x: 0, y: point.y) }
        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            scroll = nil
            lockedOriginX = nil
        }
        deinit { detach() }
    }
}
