import AppKit
import SwiftUI
import Testing
@testable import HookyBar

@Suite(.serialized) @MainActor
struct NativePaneTransitionTests {
    private func root(_ value: Int) -> AnyView { AnyView(Text("Page \(value)")) }

    @Test func rapidReversalReusesTheVisibleOutgoingPageWithoutReattachment() throws {
        let window = NSWindow(contentRect: NSRect(x: -2200, y: -2200, width: 440, height: 240),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NativePaneContainer()
        window.contentView = container
        defer { container.dispose(); container.cache.evictParked(); window.contentView = nil; window.close() }

        container.setContent(root(0), selection: 0, direction: 1, reducedMotion: false)
        let first = try #require(container.current)
        let firstProbe = PaneWindowAttachmentProbe()
        first.addSubview(firstProbe)
        container.setContent(root(1), selection: 1, direction: 1, reducedMotion: false)
        let second = try #require(container.current)
        let secondProbe = PaneWindowAttachmentProbe()
        second.addSubview(secondProbe)

        for _ in 0..<6 {
            container.setContent(root(0), selection: 0, direction: -1, reducedMotion: false)
            #expect(container.current === first)
            container.setContent(root(1), selection: 1, direction: 1, reducedMotion: false)
            #expect(container.current === second)
            #expect(container.subviews.count == 2)
        }
        #expect(firstProbe.attachments == 1)
        #expect(secondProbe.attachments == 1)
        #expect(firstProbe.detachments == 0)
        #expect(secondProbe.detachments == 0)
        #expect(container.current?.acceptsInteraction == true)
        #expect(container.outgoing?.acceptsInteraction == false)
    }

    @Test func sameSelectionReusesHostingViewAndResizeKeepsGeometry() {
        let container = NativePaneContainer()
        container.frame = NSRect(x: 0, y: 0, width: 440, height: 240)
        container.setContent(root(0), selection: 0, direction: 1, reducedMotion: false)
        let initial = container.current
        let initialAssignments = initial?.rootAssignmentCount
        for _ in 0..<30 { container.setContent(root(0), selection: 0, direction: 1, reducedMotion: false) }
        #expect(container.current === initial)
        #expect(container.current?.rootAssignmentCount == initialAssignments)
        #expect(container.subviews.count == 1)
        container.setFrameSize(NSSize(width: 380, height: 220))
        container.layoutSubtreeIfNeeded()
        #expect(container.current?.frame == container.bounds)
        container.dispose()
    }

    @Test func environmentRevisionRefreshesTheCurrentRootOnce() throws {
        let container = NativePaneContainer()
        container.setContent(
            root(0), selection: 0, direction: 1, reducedMotion: false,
            contentRevision: .testing("ru")
        )
        let host = try #require(container.current)
        let initialAssignments = host.rootAssignmentCount

        for _ in 0..<20 {
            container.setContent(
                root(0), selection: 0, direction: 1, reducedMotion: false,
                contentRevision: .testing("ru")
            )
        }
        #expect(host.rootAssignmentCount == initialAssignments)

        container.setContent(
            root(0), selection: 0, direction: 1, reducedMotion: false,
            contentRevision: .testing("en")
        )
        #expect(host.rootAssignmentCount == initialAssignments + 1)
        container.dispose()
    }

    @Test func rapidSwitchesKeepOnlyTwoPagesAndDisposeReleasesThem() async {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 240),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NativePaneContainer(cache: NativePaneCache(idleLifetime: 0.03))
        window.contentView = container // Never order the test window onscreen.
        weak var first: NativePaneHostingView?
        for value in 0..<20 {
            container.setContent(root(value), selection: value, direction: value % 2 == 0 ? 1 : -1, reducedMotion: false)
            if value == 0 { first = container.current }
            #expect(container.subviews.count <= 2)
            #expect(container.cache.retainedCount <= 4)
            #expect(container.current?.acceptsInteraction == true)
            if value > 0 { #expect(container.outgoing?.acceptsInteraction == false) }
        }
        #expect(container.current?.layer?.animation(forKey: "hooky.tab.slide") != nil)
        weak let last = container.current
        weak let outgoing = container.outgoing
        container.dispose()
        #expect(container.subviews.isEmpty)
        // AppKit/SwiftUI retain hosts until the current display transaction is
        // committed. Verify bounded eventual release, not synchronous deinit.
        try? await Task.sleep(for: .milliseconds(500))
        #expect(container.subviews.isEmpty) // Cancelled completion cannot resurrect a page.
        #expect(first == nil)
        #expect(last == nil)
        #expect(outgoing == nil)
        window.contentView = nil
        window.close()
    }

    @Test func completedTransitionParksOutgoingAndReduceMotionKeepsFadeOnly() async {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 240),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NativePaneContainer()
        window.contentView = container
        defer { container.dispose(); window.contentView = nil; window.close() }
        container.setContent(root(0), selection: 0, direction: 1, reducedMotion: true)
        container.setContent(root(1), selection: 1, direction: 1, reducedMotion: true)
        #expect(container.current?.layer?.animation(forKey: "hooky.tab.slide") == nil)
        #expect(container.current?.layer?.animation(forKey: "hooky.tab.fade") != nil)
        weak let old = container.outgoing
        try? await Task.sleep(for: .milliseconds(350))
        #expect(container.subviews.count == 1)
        #expect(container.outgoing == nil)
        #expect(old != nil)
        #expect(old?.superview == nil)
        #expect(old?.acceptsInteraction == false)
        container.cache.evictParked()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(old == nil)
    }

    @Test func revisitingAndQuickReopeningReuseHostsButIdleReleasesThem() async throws {
        let cache = NativePaneCache(idleLifetime: 0.15)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 240),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { cache.evictParked(); window.contentView = nil; window.close() }
        let container = NativePaneContainer(cache: cache)
        window.contentView = container
        container.setContent(root(0), selection: 0, direction: 1, reducedMotion: true)
        weak let initial = container.current
        for selection in [1, 2, 3, 0] {
            container.setContent(root(selection), selection: selection, direction: 1, reducedMotion: true)
            try await Task.sleep(for: .milliseconds(160))
        }
        #expect(container.current === initial)
        #expect(cache.retainedCount == 4)
        container.dispose()
        #expect(cache.parkedCount == 4)
        window.contentView = nil

        let reopened = NativePaneContainer(cache: cache)
        window.contentView = reopened
        reopened.setContent(root(0), selection: 0, direction: 1, reducedMotion: false)
        #expect(reopened.current === initial)
        #expect(reopened.current?.acceptsInteraction == true)
        try await Task.sleep(for: .milliseconds(250))
        #expect(cache.parkedCount == 3) // Cancelled idle eviction did not clear the cache.
        #expect(reopened.current === initial)
        reopened.dispose()
        try await Task.sleep(for: .milliseconds(400))
        #expect(cache.retainedCount == 0)
        #expect(initial == nil)
    }

    @Test func memoryPressureEvictionPreservesAttachedPages() {
        let cache = NativePaneCache()
        let first = cache.take(root(0), selection: 0, contentRevision: .testing())
        cache.putBack(first)
        let second = cache.take(root(1), selection: 1, contentRevision: .testing())
        cache.evictParked() // Same operation as the memory-pressure callback.
        #expect(cache.parkedCount == 0)
        #expect(cache.retainedCount == 1)
        #expect(second.acceptsInteraction)
        cache.putBack(second)
        cache.evictParked()
    }

    @Test func detachedCachedPageRepeatsAppearanceWithoutRecreatingState() async throws {
        let cache = NativePaneCache()
        let probe = PaneLifecycleProbe()
        let container = NativePaneContainer(cache: cache)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 240),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        defer { container.dispose(); cache.evictParked(); window.contentView = nil; window.close() }
        let content = AnyView(PaneLifecycleFixture(probe: probe))
        container.setContent(content, selection: 0, direction: 1, reducedMotion: true)
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        let identity = try #require(probe.identities.first)
        container.setContent(root(1), selection: 1, direction: 1, reducedMotion: true)
        try await Task.sleep(for: .milliseconds(300))
        #expect(probe.disappearances == 1)
        let evaluationsWhileParked = probe.bodyEvaluations
        for value in 1...20 { probe.revision = value }
        try await Task.sleep(for: .milliseconds(200))
        #expect(probe.bodyEvaluations == evaluationsWhileParked)
        container.setContent(content, selection: 0, direction: -1, reducedMotion: true)
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(200))
        #expect(probe.identities == [identity, identity])
        #expect(probe.seenValues == [0, 20])
    }

    @Test func actualRepresentableReleasesContainerAfterRepeatedCollapse() async throws {
        let model = PaneFixtureModel()
        let host = NSHostingView(rootView: PaneFixture(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 240),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }

        func findContainer(_ view: NSView) -> NativePaneContainer? {
            if let container = view as? NativePaneContainer { return container }
            return view.subviews.lazy.compactMap(findContainer).first
        }
        for cycle in 0..<4 {
            withAnimation(.easeInOut(duration: 0.1)) { model.expanded = true }
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(150))
            weak let container = findContainer(host)
            #expect(container != nil)
            model.selection = cycle + 1
            try await Task.sleep(for: .milliseconds(100))
            withAnimation(.easeInOut(duration: 0.1)) { model.expanded = false }
            for _ in 0..<12 where container != nil {
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(findContainer(host) == nil)
            #expect(container == nil)
        }
    }

    @Test func unrelatedParentUpdatesDoNotReplaceTheVisiblePageRoot() async throws {
        let model = PaneFixtureModel()
        model.expanded = true
        let host = NSHostingView(rootView: PaneFixture(model: model))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 240),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }

        func findContainer(_ view: NSView) -> NativePaneContainer? {
            if let container = view as? NativePaneContainer { return container }
            return view.subviews.lazy.compactMap(findContainer).first
        }

        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(150))
        let container = try #require(findContainer(host))
        let page = try #require(container.current)
        let assignments = page.rootAssignmentCount
        #expect(assignments == 1)

        for revision in 1...20 { model.parentRevision = revision }
        try await Task.sleep(for: .milliseconds(150))
        #expect(container.current === page)
        #expect(page.rootAssignmentCount == assignments)
    }
}

private final class PaneWindowAttachmentProbe: NSView {
    var attachments = 0
    var detachments = 0
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { detachments += 1 } else { attachments += 1 }
    }
}

private final class PaneFixtureModel: ObservableObject {
    let cache = NativePaneCache()
    @Published var expanded = false
    @Published var selection = 0
    @Published var parentRevision = 0
}

private struct PaneFixture: View {
    @ObservedObject var model: PaneFixtureModel
    var body: some View {
        let _ = model.parentRevision
        ZStack {
            if model.expanded {
                NativePaneTransition(selection: model.selection, direction: 1, cache: model.cache) {
                    Text("Pane \(model.selection)").hookyMaterial(cornerRadius: 12)
                }
                .transition(.opacity)
            }
        }
        .frame(width: 440, height: 240)
    }
}

private final class PaneLifecycleProbe: ObservableObject {
    @Published var revision = 0
    var bodyEvaluations = 0
    var seenValues: [Int] = []
    var identities: [UUID] = []
    var disappearances = 0
}

private final class PaneLifecycleIdentity: ObservableObject { let id = UUID() }

private struct PaneLifecycleFixture: View {
    @StateObject private var identity = PaneLifecycleIdentity()
    @ObservedObject var probe: PaneLifecycleProbe
    var body: some View {
        let _ = probe.bodyEvaluations += 1
        Text("Lifecycle \(probe.revision)")
            .onAppear {
                probe.identities.append(identity.id)
                probe.seenValues.append(probe.revision)
            }
            .onDisappear { probe.disappearances += 1 }
    }
}
