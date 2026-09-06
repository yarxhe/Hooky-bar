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
            lockAxis()
        }
        private func lockAxis() {
            guard let scroll else { return }
            scroll.hasHorizontalScroller = false
            scroll.horizontalScrollElasticity = .none
            scroll.usesPredominantAxisScrolling = true
            let clip = scroll.contentView
            if clip.bounds.origin.x != 0 {
                clip.scroll(to: Self.verticalOrigin(clip.bounds.origin))
                scroll.reflectScrolledClipView(clip)
            }
        }
        static func verticalOrigin(_ point: NSPoint) -> NSPoint { NSPoint(x: 0, y: point.y) }
        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            scroll = nil
        }
    }
}
