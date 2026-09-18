import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import HookyBar

@Suite(.serialized)
@MainActor
struct NativeSurfaceTests {
    private final class Model: ObservableObject { @Published var expanded = false }
    private struct Fixture: View {
        @ObservedObject var model: Model
        var body: some View {
            NativeSurface(surface: HookySurfaceLayout(mode: model.expanded ? .expanded : .idle,
                width: model.expanded ? 440 : 186, height: model.expanded ? 314 : 29,
                horizontalOffset: 0, bottomLeadingRadius: 9, bottomTrailingRadius: 9),
                backgroundOpacity: 1, onHover: { _ in }) {
                    Text(model.expanded ? "Expanded" : "Idle")
            }
            .frame(width: 440, height: 314)
        }
    }

    @Test func actualRepresentableReusesAndReleasesItsHost() async throws {
        let model = Model()
        let parent = NSHostingView(rootView: AnyView(Fixture(model: model)))
        let window = NSWindow(contentRect: NSRect(x: -2200, y: -2200, width: 440, height: 314),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = parent
        func find(_ view: NSView) -> NativeSurfaceView? {
            if let surface = view as? NativeSurfaceView { return surface }
            return view.subviews.lazy.compactMap { find($0) }.first
        }
        parent.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(80))
        weak let original = find(parent)
        #expect(original != nil)
        for _ in 0..<6 {
            model.expanded.toggle()
            parent.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(40))
            #expect(find(parent) === original)
            #expect(original?.host.frame.size == NSSize(width: 440, height: 314))
        }
        parent.rootView = AnyView(EmptyView())
        parent.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        #expect(original == nil)
    }

    private func layout(_ mode: HookySurfaceMode, width: CGFloat = 186, height: CGFloat = 29,
                        offset: CGFloat = 0, left: CGFloat = 9, right: CGFloat = 9) -> HookySurfaceLayout {
        HookySurfaceLayout(mode: mode, width: width, height: height, horizontalOffset: offset,
                           bottomLeadingRadius: left, bottomTrailingRadius: right)
    }

    @Test func stableRevisionDoesNotReinstallTheHostedSwiftUIRoot() {
        let view = NativeSurfaceView()
        let environment = AnyHashable("test")
        view.installContentIfNeeded(revision: AnyHashable(1), environmentRevision: environment) {
            AnyView(Text("first"))
        }
        for _ in 0..<20 {
            view.installContentIfNeeded(revision: AnyHashable(1), environmentRevision: environment) {
                AnyView(Text("redundant"))
            }
        }
        #expect(view.hostContentUpdateCount == 1)

        view.installContentIfNeeded(revision: AnyHashable(2), environmentRevision: environment) {
            AnyView(Text("changed"))
        }
        #expect(view.hostContentUpdateCount == 2)
    }

    @Test func stableGeometryDoesNotReinstallThePointerTrackingArea() {
        let view = NativeSurfaceView()
        view.frame = CGRect(x: 0, y: 0, width: 440, height: 314)
        let stable = layout(.expanded, width: 440, height: 314, left: 18, right: 18)
        view.update(surface: stable, backgroundOpacity: 1, reduceMotion: false)
        let installs = view.trackingAreaInstallCount
        for _ in 0..<100 {
            view.update(surface: stable, backgroundOpacity: 1, reduceMotion: false)
        }
        #expect(view.trackingAreaInstallCount == installs)
        view.dispose()
    }

    @Test func shellChangesDoNotResizeTheContentHost() {
        let window = NSWindow(contentRect: NSRect(x: -2200, y: -2200, width: 440, height: 314),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let view = NativeSurfaceView()
        view.frame = CGRect(x: 0, y: 0, width: 440, height: 314)
        window.contentView = view
        view.update(surface: layout(.idle), backgroundOpacity: 0.001, reduceMotion: false)
        view.layoutSubtreeIfNeeded()
        let original = view.host.frame
        let resizes = view.hostResizeCount
        #expect(view.surfaceMask.animation(forKey: "hooky.surface.shape") == nil)
        for _ in 0..<10 {
            view.update(surface: layout(.expanded, width: 440, height: 314, left: 18, right: 18),
                        backgroundOpacity: 1, reduceMotion: false)
            #expect(view.surfaceMask.animation(forKey: "hooky.surface.shape") is CABasicAnimation)
            view.layoutSubtreeIfNeeded()
            #expect(view.surfaceMask.animation(forKey: "hooky.surface.shape") != nil)
            view.update(surface: layout(.compact, width: 270, height: 32), backgroundOpacity: 1, reduceMotion: false)
            view.layoutSubtreeIfNeeded()
        }
        #expect(view.host.frame == original)
        #expect(view.hostResizeCount == resizes)
        #expect(view.subviews.count == 1)
        view.dispose()
        #expect(view.surfaceMask.animationKeys()?.isEmpty != false)
        #expect(view.layer?.animationKeys()?.isEmpty != false)
    }

    @Test func asymmetricWingsAndSuccessKeepOneTopAnchoredMask() {
        let bounds = CGRect(x: 0, y: 0, width: 440, height: 314)
        let compact = layout(.compact, width: 250, height: 32, offset: -15)
        #expect(NativeSurfaceView.rect(compact, in: bounds) == CGRect(x: 80, y: 0, width: 250, height: 32))
        let success = layout(.screenshotSuccess, width: 66, height: 32, offset: -123, right: 0)
        #expect(NativeSurfaceView.path(success, in: bounds).boundingBoxOfPath == CGRect(x: 64, y: 0, width: 66, height: 32))
        func topology(_ path: CGPath) -> [CGPathElementType] {
            var result: [CGPathElementType] = []
            path.applyWithBlock { result.append($0.pointee.type) }
            return result
        }
        let expanded = layout(.expanded, width: 440, height: 314, left: 18, right: 18)
        #expect(topology(NativeSurfaceView.path(success, in: bounds)) == topology(NativeSurfaceView.path(expanded, in: bounds)))
    }

    @Test func reduceMotionSnapsGeometryAndTransparentMarginsRejectHits() {
        let window = NSWindow(contentRect: NSRect(x: -2200, y: -2200, width: 440, height: 314),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        let view = NativeSurfaceView()
        view.frame = CGRect(x: 0, y: 0, width: 440, height: 314)
        window.contentView = view
        view.update(surface: layout(.idle), backgroundOpacity: 0.001, reduceMotion: false)
        view.layoutSubtreeIfNeeded()
        view.update(surface: layout(.expanded, width: 440, height: 314), backgroundOpacity: 1, reduceMotion: false)
        #expect(view.surfaceMask.animation(forKey: "hooky.surface.shape") != nil)
        view.update(surface: layout(.compact), backgroundOpacity: 1, reduceMotion: true)
        #expect(view.surfaceMask.animation(forKey: "hooky.surface.shape") == nil)
        #expect(view.hitTest(view.convert(CGPoint(x: 10, y: 10), to: view.superview)) == nil)
        #expect(view.hitTest(view.convert(CGPoint(x: 220, y: 100), to: view.superview)) == nil)
        #expect(view.hitTest(view.convert(CGPoint(x: 220, y: 10), to: view.superview)) != nil)
        var exits = 0
        view.onHover = { if !$0 { exits += 1 } }
        // A panel opened through global hover may not receive mouseEntered.
        // Leaving it must still schedule the ordinary collapse.
        if let event = NSEvent.enterExitEvent(with: .mouseExited, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
            context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) {
            view.mouseExited(with: event)
        }
        #expect(exits == 1)
        view.dispose()
    }

    @Test func hitTestingConvertsParentCoordinatesForAnOffsetFlippedSurface() {
        let parent = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 420))
        let view = NativeSurfaceView()
        view.frame = CGRect(x: 30, y: 50, width: 440, height: 314)
        parent.addSubview(view)
        view.update(surface: layout(.compact), backgroundOpacity: 1, reduceMotion: true)
        view.layoutSubtreeIfNeeded()
        // The shell is top-down; this plain AppKit parent is bottom-up.
        let inside = view.convert(CGPoint(x: 220, y: 10), to: parent)
        #expect(inside == CGPoint(x: 250, y: 354))
        #expect(view.hitTest(inside) != nil)
        #expect(view.hitTest(view.convert(CGPoint(x: 10, y: 10), to: parent)) == nil)
        #expect(view.hitTest(view.convert(CGPoint(x: 220, y: 100), to: parent)) == nil)
        view.isHidden = true
        #expect(view.hitTest(inside) == nil)
        view.dispose()
    }
}
