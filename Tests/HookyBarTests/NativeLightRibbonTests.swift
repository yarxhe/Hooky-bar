import AppKit
import Testing
@testable import HookyBar

@Suite(.serialized) @MainActor
struct NativeLightRibbonTests {
    @Test func geometryIsReusedAndNoContinuousAnimationIsStarted() async {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 314),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NativeLightRibbonView()
        view.frame = NSRect(x: 0, y: 0, width: 440, height: 314)
        window.contentView = view
        defer { window.contentView = nil; window.close() }
        let colors = [NSColor.red.cgColor, NSColor.blue.cgColor, NSColor.green.cgColor]
        view.update(colors: colors, active: true, reduceMotion: false)
        view.layoutSubtreeIfNeeded()
        #expect(view.animatedLayerCount == 2) // One bounded activity fade.
        view.stop()
        #expect(view.animatedLayerCount == 0)
        let builds = view.geometryBuildCount
        for _ in 0..<50 {
            view.update(colors: colors, active: true, reduceMotion: false)
            view.layoutSubtreeIfNeeded()
        }
        #expect(view.geometryBuildCount == builds)
        #expect(view.hitTest(.zero) == nil)
        let changed = [NSColor.orange.cgColor, NSColor.purple.cgColor, NSColor.cyan.cgColor]
        view.update(colors: changed, active: false, reduceMotion: false)
        #expect(view.animatedLayerCount == 2)
        view.stop()
        #expect(view.animatedLayerCount == 0)
        view.update(colors: changed, active: true, reduceMotion: true)
        #expect(view.animatedLayerCount == 0)
        window.contentView = nil
        #expect(view.animatedLayerCount == 0)
    }
}
