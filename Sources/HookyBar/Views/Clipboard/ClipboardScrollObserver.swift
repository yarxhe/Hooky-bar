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
        private var scrollMonitor: Any?
        private var initialOffset: CGFloat?

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
            initialOffset = clipView.bounds.origin.y
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) {
                [weak self, weak scrollView] event in
                guard let self, let scrollView, event.window === scrollView.window else { return event }
                let point = scrollView.convert(event.locationInWindow, from: nil)
                guard scrollView.bounds.contains(point) else { return event }
                DispatchQueue.main.async { [weak self, weak scrollView] in
                    guard let self, let scrollView else { return }
                    let currentOffset = scrollView.contentView.bounds.origin.y
                    let baseline = initialOffset ?? currentOffset
                    onOffsetChange(max(0, currentOffset - baseline))
                }
                return event
            }
        }

        func detach() {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            scrollMonitor = nil
            scrollView = nil
            initialOffset = nil
        }
    }
}
