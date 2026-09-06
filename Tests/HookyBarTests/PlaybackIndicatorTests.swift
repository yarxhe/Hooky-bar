import AppKit
import Testing
@testable import HookyBar

struct PlaybackIndicatorTests {
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
    @Test func verticalLockPreservesVerticalOffset() {
        for x in [-80.0, 0, 80] {
            #expect(VerticalScrollLock.Coordinator.verticalOrigin(NSPoint(x: x, y: 120)) == NSPoint(x: 0, y: 120))
        }
    }
}
