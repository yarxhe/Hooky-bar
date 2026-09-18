import AppKit
import QuartzCore
import SwiftUI

/// Keep page motion outside SwiftUI's layout transaction. The native compositor
/// slides/fades the hosting layers; controls inside each page keep their own
/// SwiftUI animations and the system dark blur material.
struct NativePaneTransition<Content: View>: NSViewRepresentable {
    let selection: Int
    let direction: CGFloat
    let content: Content
    let cache: NativePaneCache?

    init(selection: Int, direction: CGFloat, cache: NativePaneCache? = nil, @ViewBuilder content: () -> Content) {
        self.selection = selection
        self.direction = direction
        self.content = content()
        self.cache = cache
    }

    func makeNSView(context: Context) -> NativePaneContainer {
        let container = NativePaneContainer(cache: cache ?? NativePaneCache())
        // Build the initial hosting graph before the container reaches the
        // window. SwiftUI follows this with updateNSView, but the revision
        // guard below prevents the former second root assignment.
        updateNSView(container, context: context)
        return container
    }

    func updateNSView(_ container: NativePaneContainer, context: Context) {
        // An independent hosting root does not inherit SwiftUI environment
        // automatically. Preserve locale, material appearance and accessibility.
        let root = AnyView(
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .foregroundStyle(Color.white)
                .environment(\.self, context.environment)
        )
        container.setContent(
            root,
            selection: selection,
            direction: direction,
            reducedMotion: context.environment.accessibilityReduceMotion,
            contentRevision: NativePaneContentRevision(environment: context.environment)
        )
    }

    static func dismantleNSView(_ container: NativePaneContainer, coordinator: ()) {
        container.dispose()
    }
}

final class NativePaneHostingView: NSHostingView<AnyView> {
    var acceptsInteraction = true
    var pageID = 0
    var contentRevision: NativePaneContentRevision?
    private(set) var rootAssignmentCount = 1
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? {
        acceptsInteraction ? super.hitTest(point) : nil
    }

    func replaceRoot(_ content: AnyView, revision: NativePaneContentRevision) {
        rootView = content
        contentRevision = revision
        rootAssignmentCount += 1
    }
}

struct NativePaneContentRevision: Equatable {
    let localeIdentifier: String
    let colorScheme: ColorScheme
    let controlActiveState: ControlActiveState
    let accessibilityEnabled: Bool
    let reduceMotion: Bool
    let reduceTransparency: Bool

    init(environment: EnvironmentValues) {
        localeIdentifier = environment.locale.identifier
        colorScheme = environment.colorScheme
        controlActiveState = environment.controlActiveState
        accessibilityEnabled = environment.accessibilityEnabled
        reduceMotion = environment.accessibilityReduceMotion
        reduceTransparency = environment.accessibilityReduceTransparency
    }

    static func testing(_ token: String = "") -> Self {
        Self(
            localeIdentifier: token,
            colorScheme: .dark,
            controlActiveState: .active,
            accessibilityEnabled: false,
            reduceMotion: false,
            reduceTransparency: false
        )
    }

    private init(
        localeIdentifier: String,
        colorScheme: ColorScheme,
        controlActiveState: ControlActiveState,
        accessibilityEnabled: Bool,
        reduceMotion: Bool,
        reduceTransparency: Bool
    ) {
        self.localeIdentifier = localeIdentifier
        self.colorScheme = colorScheme
        self.controlActiveState = controlActiveState
        self.accessibilityEnabled = accessibilityEnabled
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
    }
}

/// Retain only visited pages, including at most four checked-out/parked hosts.
/// Parked pages are detached from the window/display loop. A short grace period
/// permits reopening; idle and memory-pressure eviction release their graphs.
final class NativePaneCache: ObservableObject {
    private struct WeakHost { weak var value: NativePaneHostingView? }
    private var parked: [Int: NativePaneHostingView] = [:]
    private var order: [Int] = []
    private var borrowed: [ObjectIdentifier: WeakHost] = [:]
    private var eviction: DispatchWorkItem?
    private var pressure: DispatchSourceMemoryPressure?
    let idleLifetime: TimeInterval
    static let capacity = 4

    var parkedCount: Int { parked.count }
    var retainedCount: Int { parked.count + borrowed.values.filter { $0.value != nil }.count }

    init(idleLifetime: TimeInterval = 8) {
        self.idleLifetime = idleLifetime
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self] in self?.evictParked() }
        source.resume()
        pressure = source
    }

    func take(
        _ content: AnyView,
        selection: Int,
        contentRevision: NativePaneContentRevision
    ) -> NativePaneHostingView {
        dispatchPrecondition(condition: .onQueue(.main))
        eviction?.cancel()
        eviction = nil
        let host: NativePaneHostingView
        if let previous = parked.removeValue(forKey: selection) {
            order.removeAll { $0 == selection }
            host = previous
            // Observed models keep the detached graph current and SwiftUI
            // evaluates pending invalidations when AppKit reattaches it. Only
            // rebuild for an actual environment change; rebuilding on every
            // tab visit was the largest tab-switch CPU spike.
            if host.contentRevision != contentRevision {
                host.replaceRoot(content, revision: contentRevision)
            }
            HookyDiagnostics.control("component=pane action=host_reuse page=\(selection)")
        } else {
            host = NativePaneHostingView(rootView: content)
            host.pageID = selection
            host.contentRevision = contentRevision
            host.sizingOptions = []
            host.wantsLayer = true
            host.layer?.backgroundColor = NSColor.clear.cgColor
            host.autoresizingMask = [.width, .height]
            HookyDiagnostics.control("component=pane action=host_create page=\(selection)")
        }
        borrowed[ObjectIdentifier(host)] = WeakHost(value: host)
        trim()
        host.acceptsInteraction = true
        host.setAccessibilityHidden(false)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        host.layer?.opacity = 1
        host.layer?.transform = CATransform3DIdentity
        host.layer?.zPosition = 0
        CATransaction.commit()
        return host
    }

    func putBack(_ host: NativePaneHostingView) {
        dispatchPrecondition(condition: .onQueue(.main))
        host.acceptsInteraction = false
        host.setAccessibilityHidden(true)
        host.layer?.removeAllAnimations()
        host.removeFromSuperview()
        borrowed.removeValue(forKey: ObjectIdentifier(host))
        // A second container must never steal an attached page. If two leases
        // return the same page ID, keep only the last completed one.
        if let previous = parked[host.pageID], previous !== host { release(previous) }
        parked[host.pageID] = host
        order.removeAll { $0 == host.pageID }
        order.append(host.pageID)
        trim()
    }

    func scheduleIdleEviction() {
        borrowed = borrowed.filter { $0.value.value != nil }
        guard borrowed.isEmpty else { return }
        eviction?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.evictParked()
            self.eviction = nil
        }
        eviction = work
        DispatchQueue.main.asyncAfter(deadline: .now() + idleLifetime, execute: work)
    }

    func evictParked() {
        dispatchPrecondition(condition: .onQueue(.main))
        for host in parked.values { release(host) }
        parked.removeAll()
        order.removeAll()
    }

    private func trim() {
        borrowed = borrowed.filter { $0.value.value != nil }
        while parked.count + borrowed.count > Self.capacity, let key = order.first {
            order.removeFirst()
            if let host = parked.removeValue(forKey: key) { release(host) }
        }
    }

    private func release(_ host: NativePaneHostingView) {
        host.layer?.removeAllAnimations()
        host.rootView = AnyView(EmptyView())
    }

    deinit {
        eviction?.cancel()
        pressure?.cancel()
    }
}

final class NativePaneContainer: NSView {
    private(set) var selection: Int?
    private(set) var current: NativePaneHostingView?
    private(set) var outgoing: NativePaneHostingView?
    private var completion: DispatchWorkItem?
    private var generation: UInt = 0
    let cache: NativePaneCache
    static let transitionDuration = 0.22

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    init(cache: NativePaneCache = NativePaneCache()) {
        self.cache = cache
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The existing outer shell keeps its expansion animation. Within a tab
        // transition these frames stay still: only compositor properties move.
        for host in [current, outgoing].compactMap({ $0 }) where host.frame != bounds {
            host.frame = bounds
        }
        CATransaction.commit()
    }

    func setContent(
        _ content: AnyView,
        selection: Int,
        direction: CGFloat,
        reducedMotion: Bool,
        contentRevision: NativePaneContentRevision = .testing()
    ) {
        if self.selection == selection, let current {
            // Every observed object used by a page is observed by that page as
            // well. Replacing the hosting root for unrelated parent updates
            // invalidates the complete AttributeGraph for no visual change.
            if current.contentRevision != contentRevision {
                current.replaceRoot(content, revision: contentRevision)
                HookyDiagnostics.control("component=pane action=environment_refresh page=\(selection)")
            }
            return
        }

        generation &+= 1
        let transition = generation
        completion?.cancel()
        completion = nil

        // Reversing a transition should not detach and reattach a page that is
        // already on screen. That repeats AppKit/SwiftUI appearance and layout.
        let returning = outgoing?.pageID == selection ? outgoing : nil
        let returningX = returning.map { shownTranslation($0) }
        let returningOpacity = returning.map { shownOpacity($0) }
        if returning != nil { outgoing = nil } else { releaseOutgoing() }

        let previous = current
        let previousX = previous.map { shownTranslation($0) } ?? 0
        let previousOpacity = previous.map { shownOpacity($0) } ?? 1
        previous?.layer?.removeAllAnimations()
        previous?.acceptsInteraction = false
        previous?.setAccessibilityHidden(true)

        let incoming: NativePaneHostingView
        if let returning {
            incoming = returning
            incoming.layer?.removeAllAnimations()
            if incoming.contentRevision != contentRevision {
                incoming.replaceRoot(content, revision: contentRevision)
            }
            incoming.acceptsInteraction = true
            incoming.setAccessibilityHidden(false)
            HookyDiagnostics.control("component=pane action=host_reverse page=\(selection)")
        } else {
            incoming = cache.take(
                content,
                selection: selection,
                contentRevision: contentRevision
            )
            if incoming.frame != bounds { incoming.frame = bounds }
            addSubview(incoming)
        }
        current = incoming
        self.selection = selection
        // Let AppKit lay out once in its normal display pass, before committing
        // the layer animations. Do not recursively render inside updateNSView.

        guard let previous, window != nil else {
            discard(previous)
            return
        }
        outgoing = previous
        let duration = reducedMotion ? 0.12 : Self.transitionDuration
        let sign: CGFloat = direction < 0 ? -1 : 1

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        incoming.layer?.opacity = 1
        incoming.layer?.transform = CATransform3DIdentity
        incoming.layer?.zPosition = 1
        previous.layer?.zPosition = 0
        previous.layer?.opacity = 0
        previous.layer?.transform = CATransform3DMakeTranslation(reducedMotion ? 0 : -12 * sign, 0, 0)
        CATransaction.commit()

        if !reducedMotion {
            incoming.layer?.add(slide(from: returningX ?? Double(14 * sign), to: 0, duration: duration), forKey: "hooky.tab.slide")
            previous.layer?.add(slide(from: previousX, to: Double(-12 * sign), duration: duration), forKey: "hooky.tab.slide")
        }
        incoming.layer?.add(fade(from: Double(returningOpacity ?? 0), to: 1, duration: reducedMotion ? duration : 0.2), forKey: "hooky.tab.fade")
        previous.layer?.add(fade(from: Double(previousOpacity), to: 0, duration: duration), forKey: "hooky.tab.fade")

        // A bounded, cancellable cleanup also works if the panel is hidden in
        // the middle of an animation. No screenshot textures are retained.
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.generation == transition else { return }
            self.releaseOutgoing()
            self.completion = nil
        }
        completion = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02, execute: work)
    }

    func dispose() {
        generation &+= 1
        completion?.cancel()
        completion = nil
        releaseOutgoing()
        discard(current)
        current = nil
        selection = nil
        cache.scheduleIdleEviction()
    }

    private func releaseOutgoing() {
        discard(outgoing)
        outgoing = nil
    }

    private func discard(_ host: NativePaneHostingView?) {
        if let host { cache.putBack(host) }
    }

    private func shownTranslation(_ host: NativePaneHostingView) -> Double {
        (host.layer?.presentation()?.value(forKeyPath: "transform.translation.x") as? NSNumber)?.doubleValue
            ?? ((host.layer?.animation(forKey: "hooky.tab.slide") as? CABasicAnimation)?.fromValue as? NSNumber)?.doubleValue
            ?? (host.layer?.value(forKeyPath: "transform.translation.x") as? NSNumber)?.doubleValue ?? 0
    }

    private func shownOpacity(_ host: NativePaneHostingView) -> Double {
        host.layer?.presentation().map { Double($0.opacity) }
            ?? ((host.layer?.animation(forKey: "hooky.tab.fade") as? CABasicAnimation)?.fromValue as? NSNumber)?.doubleValue
            ?? Double(host.layer?.opacity ?? 1)
    }

    private func slide(from: Double, to: Double, duration: Double) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "transform.translation.x")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .default)
        return animation
    }

    private func fade(from: Double, to: Double, duration: Double) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .default)
        return animation
    }

    deinit { completion?.cancel() }
}
