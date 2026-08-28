import SwiftUI

enum HookyMotion {
    static let expandFromCompact = Animation.spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.04)
    static let collapseToCompact = Animation.spring(response: 0.42, dampingFraction: 0.9, blendDuration: 0.04)
    static let collapseToIdle = Animation.spring(response: 0.48, dampingFraction: 0.78, blendDuration: 0.05)
    static let contentFade = Animation.easeInOut(duration: 0.18)
    static let tabSwitch = Animation.spring(response: 0.34, dampingFraction: 0.9, blendDuration: 0.05)
    static let trackSwitch = Animation.spring(response: 0.42, dampingFraction: 0.88, blendDuration: 0.08)
    static let artworkArrival = Animation.spring(response: 0.38, dampingFraction: 0.9, blendDuration: 0.06)
    static let backgroundPalette = Animation.easeInOut(duration: 0.72)
}

/// Короткий сдвиг сохраняет ощущение направления, не унося экран целиком за границы острова.
struct HookyTabTransitionModifier: ViewModifier {
    let horizontalOffset: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .offset(x: horizontalOffset)
            .scaleEffect(0.992)
            .opacity(opacity)
    }
}
