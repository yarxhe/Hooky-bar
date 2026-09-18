import AppKit
import CoreImage
import QuartzCore
import SwiftUI

/// Prepare soft ribbons only when their geometry/palette changes. Palette and
/// activity changes use short native Core Animation fades; no layer animates
/// forever while the panel is open.
struct NativeLightRibbons: NSViewRepresentable {
    let palette: BackgroundPalette
    let active: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> NativeLightRibbonView { NativeLightRibbonView() }

    func updateNSView(_ view: NativeLightRibbonView, context: Context) {
        view.update(colors: palette.colors.map { NSColor($0).cgColor },
                    active: active, reduceMotion: reduceMotion)
    }

    static func dismantleNSView(_ view: NativeLightRibbonView, coordinator: ()) { view.stop() }
}

final class NativeLightRibbonView: NSView {
    private struct Ribbon {
        let surface = CALayer()
        let gradient = CAGradientLayer()
        let shape = CAShapeLayer()
    }
    private let ribbons = [Ribbon(), Ribbon()]
    private var colors: [CGColor] = []
    private var requestedActive = false
    private var reducedMotion = false
    private var preparedSize = CGSize.zero
    private(set) var geometryBuildCount = 0
    var animatedLayerCount: Int {
        ribbons.filter {
            $0.surface.animationKeys()?.isEmpty == false || $0.gradient.animationKeys()?.isEmpty == false
        }.count
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(false)
        setAccessibilityHidden(true)
        for ribbon in ribbons {
            ribbon.surface.shouldRasterize = true
            ribbon.surface.filters = [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 22])!]
            ribbon.surface.compositingFilter = CIFilter(name: "CIScreenBlendMode")
            ribbon.gradient.startPoint = CGPoint(x: -0.15, y: 0)
            ribbon.gradient.endPoint = CGPoint(x: 1.15, y: 1)
            ribbon.gradient.locations = [0, 0.28, 0.6, 1]
            ribbon.shape.fillColor = NSColor.white.cgColor
            ribbon.gradient.mask = ribbon.shape
            ribbon.surface.addSublayer(ribbon.gradient)
            layer?.addSublayer(ribbon.surface)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(colors: [CGColor], active: Bool, reduceMotion: Bool) {
        let paletteChanged = self.colors != colors && !colors.isEmpty
        let activityChanged = requestedActive != active
        let canAnimate = window != nil && !reduceMotion
        if paletteChanged {
            self.colors = colors
            for (index, ribbon) in ribbons.enumerated() {
                let next = [NSColor.clear.cgColor,
                    colors[index % colors.count].copy(alpha: 0.55)!,
                    colors[(index + 1) % colors.count].copy(alpha: 0.85)!, NSColor.clear.cgColor]
                let displayed = ribbon.gradient.presentation()?.colors ?? ribbon.gradient.colors
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                ribbon.gradient.colors = next
                CATransaction.commit()
                ribbon.gradient.removeAnimation(forKey: "hooky.light.palette")
                if canAnimate, let displayed {
                    let animation = CABasicAnimation(keyPath: "colors")
                    animation.fromValue = displayed
                    animation.toValue = next
                    animation.duration = 0.30
                    animation.timingFunction = CAMediaTimingFunction(name: .default)
                    ribbon.gradient.add(animation, forKey: "hooky.light.palette")
                }
            }
        }
        requestedActive = active
        reducedMotion = reduceMotion
        if activityChanged {
            for ribbon in ribbons {
                let target: Float = active ? 1 : 0.82
                let displayed = ribbon.surface.presentation()?.opacity ?? ribbon.surface.opacity
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                ribbon.surface.opacity = target
                CATransaction.commit()
                ribbon.surface.removeAnimation(forKey: "hooky.light.activity")
                if canAnimate {
                    let animation = CABasicAnimation(keyPath: "opacity")
                    animation.fromValue = displayed
                    animation.toValue = target
                    animation.duration = 0.18
                    animation.timingFunction = CAMediaTimingFunction(name: .default)
                    ribbon.surface.add(animation, forKey: "hooky.light.activity")
                }
            }
        }
        if reduceMotion { stop() }
    }

    override func layout() {
        super.layout()
        guard bounds.size != preparedSize, bounds.width > 0, bounds.height > 0 else { return }
        preparedSize = bounds.size
        geometryBuildCount += 1
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (index, ribbon) in ribbons.enumerated() {
            ribbon.surface.bounds = CGRect(origin: .zero, size: bounds.size)
            ribbon.surface.position = CGPoint(x: bounds.midX, y: bounds.midY)
            ribbon.gradient.frame = ribbon.surface.bounds
            ribbon.shape.frame = ribbon.gradient.bounds
            ribbon.shape.path = Self.path(in: bounds.size, phase: Double(index) * 2.8)
        }
        CATransaction.commit()
        updateScale()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateScale()
    }

    override func viewDidHide() { super.viewDidHide(); stop() }

    private func updateScale() {
        let scale = window?.backingScaleFactor ?? 2
        for ribbon in ribbons where ribbon.surface.rasterizationScale != scale {
            ribbon.surface.rasterizationScale = scale
            ribbon.gradient.contentsScale = scale
            ribbon.shape.contentsScale = scale
        }
    }

    func stop() {
        for ribbon in ribbons {
            ribbon.surface.removeAllAnimations()
            ribbon.gradient.removeAllAnimations()
        }
    }

    private static func path(in size: CGSize, phase: Double) -> CGPath {
        var upper: [CGPoint] = []
        var lower: [CGPoint] = []
        for index in 0...32 {
            let x = Double(index) / 32 * 1.4 - 0.2
            let center = 0.5 + sin(x * 4.8 + phase) * 0.15 + cos(x * 2.4 + phase) * 0.09
            let halfWidth = 0.065 + (sin(x * 3.2 + phase) + 1) * 0.035
            upper.append(CGPoint(x: x * size.width, y: (center - halfWidth) * size.height))
            lower.append(CGPoint(x: x * size.width, y: (center + halfWidth) * size.height))
        }
        let path = CGMutablePath()
        path.addLines(between: upper + lower.reversed())
        path.closeSubpath()
        return path
    }
}
