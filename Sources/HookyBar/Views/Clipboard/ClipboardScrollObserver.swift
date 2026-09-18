import AppKit
import SwiftUI

/// Реагирует только на настоящий жест прокрутки внутри NSScrollView.
struct ClipboardScrollObserver: NSViewRepresentable {
    let onOffsetChange: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOffsetChange: onOffsetChange)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.attach(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onOffsetChange = onOffsetChange
        if context.coordinator.scrollView == nil {
            DispatchQueue.main.async { context.coordinator.attach(from: nsView) }
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var onOffsetChange: (CGFloat) -> Void
        weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?
        private var initialOffset: CGFloat?
        private var callbackPending = false
        private var attachmentGeneration = 0

        init(onOffsetChange: @escaping (CGFloat) -> Void) {
            self.onOffsetChange = onOffsetChange
        }

        func attach(from view: NSView) {
            guard scrollView == nil else { return }
            var ancestor = view.superview
            while let current = ancestor, !(current is NSScrollView) {
                ancestor = current.superview
            }
            guard let scrollView = ancestor as? NSScrollView else { return }
            self.scrollView = scrollView
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            initialOffset = clipView.bounds.origin.y
            let generation = attachmentGeneration
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, scrollView != nil, !callbackPending else { return }
                callbackPending = true
                DispatchQueue.main.async { [weak self, weak scrollView] in
                    guard let self else { return }
                    callbackPending = false
                    guard attachmentGeneration == generation, let scrollView else { return }
                    let currentOffset = scrollView.contentView.bounds.origin.y
                    let baseline = initialOffset ?? currentOffset
                    onOffsetChange(max(0, currentOffset - baseline))
                }
            }
        }

        func detach() {
            attachmentGeneration &+= 1
            if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
            boundsObserver = nil
            callbackPending = false
            scrollView = nil
            initialOffset = nil
        }

        deinit { detach() }
    }
}
