import AppKit
import QuartzCore
import SwiftUI

/// A compositor-backed spectrum. SwiftUI owns only the small native view;
/// stable CALayers are resized in place without rebuilding a Canvas/Path tree.
struct SpectrumView: View {
    let signal: AudioSpectrumSignal
    var colors: [Color] = [.indigo]
    let active: Bool
    var expanded = false
    var simulated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NativeSpectrumRepresentable(
            signal: signal,
            active: active,
            expanded: expanded,
            simulated: simulated,
            reduceMotion: reduceMotion
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct NativeSpectrumRepresentable: NSViewRepresentable {
    let signal: AudioSpectrumSignal
    let active: Bool
    let expanded: Bool
    let simulated: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> NativeSpectrumView { NativeSpectrumView() }

    func updateNSView(_ view: NativeSpectrumView, context: Context) {
        view.update(
            signal: signal,
            active: active,
            expanded: expanded,
            simulated: simulated,
            reduceMotion: reduceMotion
        )
    }

    static func dismantleNSView(_ view: NativeSpectrumView, coordinator: ()) { view.stop() }
}

final class NativeSpectrumView: NSView {
    private let bars = (0..<12).map { _ in CALayer() }
    private var signal = AudioSpectrumSignal.shared
    private var timer: Timer?
    private var active = false
    private var expanded = false
    private var simulated = false
    private var reduceMotion = false
    private var levels = [CGFloat](repeating: 0, count: 12)
    private(set) var renderTickCount = 0
    var timerActive: Bool { timer != nil }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        for bar in bars {
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.85).cgColor
            layer?.addSublayer(bar)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(
        signal: AudioSpectrumSignal,
        active: Bool,
        expanded: Bool,
        simulated: Bool,
        reduceMotion: Bool
    ) {
        self.signal = signal
        self.active = active
        self.expanded = expanded
        self.simulated = simulated
        self.reduceMotion = reduceMotion
        updateTimer()
        render(at: Date())
    }

    override func layout() {
        super.layout()
        layoutBars()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTimer()
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateTimer()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateTimer()
    }

    private func updateTimer() {
        let shouldRun = active && !reduceMotion && window != nil && !isHiddenOrHasHiddenAncestor
        guard shouldRun else {
            stopTimer()
            if !active || reduceMotion {
                levels = Array(repeating: 0, count: 12)
                layoutBars()
            }
            return
        }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] timer in
            guard let self, self.window != nil, !self.isHiddenOrHasHiddenAncestor else {
                self?.stopTimer()
                return
            }
            self.render(at: timer.fireDate)
        }
        timer.tolerance = 0.012
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func render(at date: Date) {
        levels = active && !reduceMotion
            ? (simulated ? AudioSpectrumSignal.simulatedBands(at: date) : signal.snapshot(at: date).bands)
            : Array(repeating: 0, count: 12)
        renderTickCount &+= 1
        layoutBars()
    }

    private func layoutBars() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let count = expanded ? 12 : 9
        let width: CGFloat = expanded ? 3 : 2.5
        let spacing: CGFloat = expanded ? 4 : 2
        let totalWidth = CGFloat(count) * width + CGFloat(count - 1) * spacing
        let startX = (bounds.width - totalWidth) / 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, bar) in bars.enumerated() {
            guard index < count else { bar.isHidden = true; continue }
            bar.isHidden = false
            let band = levels.isEmpty ? -1 : min(levels.count - 1, index * levels.count / count)
            let level = band >= 0 ? levels[band] : 0
            let height = 3 + level * max(0, bounds.height - 3)
            bar.frame = CGRect(
                x: startX + CGFloat(index) * (width + spacing),
                y: (bounds.height - height) / 2,
                width: width,
                height: height
            )
            bar.cornerRadius = width / 2
            bar.backgroundColor = NSColor.white.withAlphaComponent(active ? 0.85 : 0.30).cgColor
        }
        CATransaction.commit()
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        stopTimer()
        bars.forEach { $0.removeAllAnimations() }
    }

    deinit { timer?.invalidate() }
}

struct CompactSpectrumView: View {
    let signal: AudioSpectrumSignal
    var colors: [Color] = [.indigo]
    let active: Bool
    var simulated = false

    var body: some View {
        SpectrumView(signal: signal, colors: colors, active: active, expanded: false, simulated: simulated)
    }
}
