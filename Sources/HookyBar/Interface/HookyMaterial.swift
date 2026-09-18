import SwiftUI

/// A plain system blur, without Liquid Glass refraction, morphing or lighting.
/// Keep the material dark regardless of the foreground application's appearance.
struct HookyMaterialBackground: View {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HookyMaterialSurface(cornerRadius: cornerRadius, reduceTransparency: reduceTransparency)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

struct HookyMaterialSurface: View {
    let cornerRadius: CGFloat
    let reduceTransparency: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if reduceTransparency {
                shape.fill(HookyTheme.materialOpaqueFill)
            } else {
                shape.fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay { shape.fill(HookyTheme.materialShade) }
            }
        }
    }
}

extension View {
    func hookyMaterial(enabled: Bool = true, cornerRadius: CGFloat) -> some View {
        // Only the decoration is conditional. Branching around `self` also
        // replaces the control's identity when selection changes.
        background {
            if enabled { HookyMaterialBackground(cornerRadius: cornerRadius) }
        }
    }
}
