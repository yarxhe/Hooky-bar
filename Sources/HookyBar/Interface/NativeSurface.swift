import AppKit
import QuartzCore
import SwiftUI

/// Animate only the shell's mask, not the frame proposed to the SwiftUI tree.
/// The live content keeps native controls, focus, and its own local animations.
struct NativeSurface<Content: View>: NSViewRepresentable {
    let surface: HookySurfaceLayout
    let backgroundOpacity: Double
    var contentRevision: AnyHashable?
    let onHover: (Bool) -> Void
    @ViewBuilder let content: () -> Content

    init(
        surface: HookySurfaceLayout,
        backgroundOpacity: Double,
        contentRevision: AnyHashable? = nil,
        onHover: @escaping (Bool) -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.surface = surface
        self.backgroundOpacity = backgroundOpacity
        self.contentRevision = contentRevision
        self.onHover = onHover
        self.content = content
    }

    func makeNSView(context: Context) -> NativeSurfaceView { NativeSurfaceView() }

    func updateNSView(_ view: NativeSurfaceView, context: Context) {
        view.onHover = onHover
        let environmentRevision = AnyHashable([
            context.environment.locale.identifier,
            String(context.environment.accessibilityEnabled),
            String(context.environment.accessibilityReduceMotion),
            String(context.environment.accessibilityReduceTransparency)
        ])
        view.installContentIfNeeded(
            revision: contentRevision,
            environmentRevision: environmentRevision
        ) {
            AnyView(content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .environment(\.self, context.environment))
        }
        view.update(surface: surface, backgroundOpacity: backgroundOpacity,
                    reduceMotion: context.environment.accessibilityReduceMotion)
    }

    static func dismantleNSView(_ view: NativeSurfaceView, coordinator: ()) { view.dispose() }
}

final class NativeSurfaceView: NSView {
    let host = NativePaneHostingView(rootView: AnyView(EmptyView()))
    let surfaceMask = CAShapeLayer()
    private(set) var surface: HookySurfaceLayout?
    private(set) var hostResizeCount = 0
    private var reducedMotion = false
    private var backgroundOpacity: Double = 0.001
    private var tracking: NSTrackingArea?
    private var trackingRect: CGRect?
    private var pointerWasInside = false
    private(set) var trackingAreaInstallCount = 0
    private var hostedRevision: AnyHashable?
    private var hostedEnvironmentRevision: AnyHashable?
    private var hasHostedContent = false
    private(set) var hostContentUpdateCount = 0
    var onHover: ((Bool) -> Void)?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.mask = surfaceMask
        surfaceMask.fillColor = NSColor.white.cgColor
        host.sizingOptions = []
        host.wantsLayer = true
        host.autoresizingMask = []
        host.setAccessibilityHidden(false)
        addSubview(host)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func installContentIfNeeded(
        revision: AnyHashable?,
        environmentRevision: AnyHashable,
        content: () -> AnyView
    ) {
        let revisionChanged = revision == nil || hostedRevision != revision
        guard !hasHostedContent || revisionChanged || hostedEnvironmentRevision != environmentRevision else { return }
        host.rootView = content()
        // The host starts with EmptyView. Explicitly unhide its accessibility
        // subtree when the real panel content is installed.
        host.setAccessibilityHidden(false)
        hostedRevision = revision
        hostedEnvironmentRevision = environmentRevision
        hasHostedContent = true
        hostContentUpdateCount &+= 1
    }

    func update(surface: HookySurfaceLayout, backgroundOpacity: Double, reduceMotion: Bool) {
        let previous = self.surface
        self.surface = surface
        self.backgroundOpacity = backgroundOpacity
        reducedMotion = reduceMotion
        updateMask(previous: previous, animate: window != nil && previous != nil)
        refreshTrackingAreaIfNeeded()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if host.frame != bounds { host.frame = bounds; hostResizeCount += 1 }
        surfaceMask.frame = bounds
        CATransaction.commit()
        updateMask(previous: surface, animate: false)
    }

    private func updateMask(previous: HookySurfaceLayout?, animate: Bool) {
        guard let surface, bounds.width > 0, bounds.height > 0 else { return }
        let path = Self.path(surface, in: bounds)
        let oldPath = surfaceMask.path
        let displayed = surfaceMask.presentation()?.path ?? oldPath
        let pathChanged = oldPath != path
        let oldColor = layer?.backgroundColor
        let color = NSColor.black.withAlphaComponent(backgroundOpacity).cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceMask.frame = bounds
        surfaceMask.path = path
        layer?.backgroundColor = color
        CATransaction.commit()

        if pathChanged {
            // A rapid reversal starts from what is currently on screen.
            surfaceMask.removeAnimation(forKey: "hooky.surface.shape")
            if animate, !reducedMotion, let displayed {
                // A short native Core Animation transition avoids the long
                // spring tail that kept the mask rendering after the panel had
                // already reached its destination.
                let animation = CABasicAnimation(keyPath: "path")
                animation.fromValue = displayed
                animation.toValue = path
                animation.duration = 0.26
                animation.timingFunction = CAMediaTimingFunction(name: .default)
                surfaceMask.add(animation, forKey: "hooky.surface.shape")
            }
        } else if reducedMotion {
            surfaceMask.removeAnimation(forKey: "hooky.surface.shape")
        }
        if oldColor != color, animate, let oldColor {
            let animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.fromValue = layer?.presentation()?.backgroundColor ?? oldColor
            animation.toValue = color
            animation.duration = 0.18
            animation.timingFunction = CAMediaTimingFunction(name: .default)
            layer?.add(animation, forKey: "hooky.surface.background")
        }
    }

    static func rect(_ surface: HookySurfaceLayout, in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.midX - surface.width / 2 + surface.horizontalOffset,
               y: bounds.minY, width: surface.width, height: surface.height)
    }

    static func path(_ surface: HookySurfaceLayout, in bounds: CGRect) -> CGPath {
        let rect = rect(surface, in: bounds)
        let left = min(surface.bottomLeadingRadius, min(rect.width / 2, rect.height))
        let right = min(surface.bottomTrailingRadius, min(rect.width / 2, rect.height))
        let path = CGMutablePath()
        // Keep command topology identical, even when a corner radius is zero.
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - right))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - right, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + left, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - left),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // AppKit passes hit-test points in the superview's coordinate system.
        let local = convert(point, from: superview)
        guard let surface, Self.rect(surface, in: bounds).contains(local) else { return nil }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingAreaIfNeeded()
    }

    private func refreshTrackingAreaIfNeeded() {
        guard let surface else { tracking = nil; return }
        let rect = Self.rect(surface, in: bounds)
        guard tracking == nil || trackingRect != rect else { return }
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: rect,
            options: [.activeAlways, .mouseEnteredAndExited, .enabledDuringMouseDrag],
            owner: self, userInfo: nil)
        tracking = area
        trackingRect = rect
        addTrackingArea(area)
        trackingAreaInstallCount &+= 1
    }

    override func mouseEntered(with event: NSEvent) {
        pointerWasInside = true
        onHover?(true)
    }
    override func mouseExited(with event: NSEvent) {
        pointerWasInside = false
        onHover?(false)
    }

    func dispose() {
        onHover = nil
        surfaceMask.removeAllAnimations()
        layer?.removeAllAnimations()
        host.rootView = AnyView(EmptyView())
        hostedRevision = nil
        hostedEnvironmentRevision = nil
        hasHostedContent = false
        if let tracking { removeTrackingArea(tracking); self.tracking = nil }
        trackingRect = nil
    }
}
