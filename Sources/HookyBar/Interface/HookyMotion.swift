import SwiftUI

enum HookyMotion {
    // Use the system motion curves. They are bounded, interruptible and do not
    // spend extra frames settling an off-screen spring after a panel closes.
    static let expandFromCompact = Animation.smooth(duration: 0.30)
    static let collapseToCompact = Animation.smooth(duration: 0.26)
    static let compactWingResize = Animation.smooth(duration: 0.22)
    static let collapseToIdle = Animation.smooth(duration: 0.28)
    static let contentFade = Animation.default
    static let tabSwitch = Animation.snappy(duration: 0.22)
    static let trackSwitch = Animation.smooth(duration: 0.24)
    static let artworkArrival = Animation.smooth(duration: 0.22)
    static let backgroundPalette = Animation.smooth(duration: 0.30)
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
