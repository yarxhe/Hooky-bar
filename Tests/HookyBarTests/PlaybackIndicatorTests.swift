import AppKit
import Testing
@testable import HookyBar

struct PlaybackIndicatorTests {
    @MainActor @Test func nativeSpectrumStopsItsClockWhenInactiveOrDetached() async {
        let window = NSWindow(contentRect: NSRect(x: -2200, y: -2200, width: 104, height: 18),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NativeSpectrumView()
        view.frame = NSRect(x: 0, y: 0, width: 104, height: 18)
        window.contentView = view
        view.update(signal: AudioSpectrumSignal(), active: true, expanded: true,
                    simulated: true, reduceMotion: false)
        #expect(view.timerActive)
        let firstTicks = view.renderTickCount
        try? await Task.sleep(for: .milliseconds(180))
        #expect(view.renderTickCount > firstTicks)
        view.update(signal: AudioSpectrumSignal(), active: false, expanded: true,
                    simulated: false, reduceMotion: false)
        #expect(!view.timerActive)
        window.contentView = nil
        #expect(!view.timerActive)
        window.close()
    }

    @MainActor @Test func nativeScrollViewDisablesSidewaysElasticity() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 1000))
        let marker = NSView(frame: .zero)
        scroll.documentView = document
        document.addSubview(marker)
        scroll.hasHorizontalScroller = true
        scroll.horizontalScrollElasticity = .allowed
        let coordinator = VerticalScrollLock.Coordinator()
        coordinator.attach(from: marker)
        #expect(!scroll.hasHorizontalScroller)
        #expect(scroll.horizontalScrollElasticity == .none)
        #expect(scroll.usesPredominantAxisScrolling)
        coordinator.detach()
    }

    @Test func indicatorIsBoundedContinuousAndStopsOnPause() {
        for index in 0..<12 {
            for step in 0..<100 {
                let time = Double(step) / 10
                let a = PlaybackIndicator.level(at: time, index: index, active: true, reducedMotion: false)
                let b = PlaybackIndicator.level(at: time + 1.0 / 30, index: index, active: true, reducedMotion: false)
                #expect((0...1).contains(a))
                #expect(abs(a - b) < 0.08)
            }
            #expect(PlaybackIndicator.level(at: 1, index: index, active: false, reducedMotion: false) == 0)
            #expect(PlaybackIndicator.level(at: 1, index: index, active: true, reducedMotion: true)
                    == PlaybackIndicator.level(at: 100, index: index, active: true, reducedMotion: true))
        }
    }

    @MainActor @Test func axisLockDoesNotFightNativeInsetsOrRewriteSettingsDuringScrolling() {
        let scroll = CountingScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        let clip = InsetClipView(frame: scroll.bounds)
        scroll.contentView = clip
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 1000))
        scroll.documentView = document
        let marker = NSView(frame: .zero)
        document.addSubview(marker)
        let coordinator = VerticalScrollLock.Coordinator()
        coordinator.attach(from: marker)
        defer { coordinator.detach() }
        let writes = scroll.horizontalScrollerWrites
        clip.correctionCalls = 0
        // Model a native clip view whose inset-adjusted legal x is not zero.
        clip.setBoundsOrigin(NSPoint(x: -12, y: 120))
        for _ in 0..<120 {
            NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: clip)
        }
        #expect(clip.correctionCalls == 0)
        #expect(clip.bounds.origin == NSPoint(x: -12, y: 120))
        #expect(scroll.horizontalScrollerWrites == writes)
        clip.setBoundsOrigin(NSPoint(x: 40, y: 180))
        #expect(clip.bounds.origin == NSPoint(x: -12, y: 180))
        #expect(clip.correctionCalls == 1)
    }
    @Test func verticalLockPreservesVerticalOffset() {
        for x in [-80.0, 0, 80] {
            #expect(VerticalScrollLock.Coordinator.verticalOrigin(NSPoint(x: x, y: 120)) == NSPoint(x: 0, y: 120))
        }
    }
}

private final class CountingScrollView: NSScrollView {
    var horizontalScrollerWrites = 0
    override var hasHorizontalScroller: Bool {
        didSet { horizontalScrollerWrites += 1 }
    }
}

private final class InsetClipView: NSClipView {
    var correctionCalls = 0
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrained = proposedBounds
        constrained.origin.x = -12
        return constrained
    }
    override func scroll(to newOrigin: NSPoint) {
        correctionCalls += 1
        super.scroll(to: newOrigin)
    }
}
