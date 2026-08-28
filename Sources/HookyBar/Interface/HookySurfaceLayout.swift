import Foundation

enum HookySurfaceMode: Equatable {
    case idle
    case compact
    case systemEvent(UUID)
    case screenshotSuccess
    case expanded
    case screenshotPreview
}

struct HookySurfaceLayout: Equatable {
    let mode: HookySurfaceMode
    let width: CGFloat
    let height: CGFloat
    let horizontalOffset: CGFloat
    let bottomLeadingRadius: CGFloat
    let bottomTrailingRadius: CGFloat

    var isIdle: Bool { mode == .idle }
}

extension InterfaceModel {
    /// Один источник геометрии для SwiftUI-поверхности и AppKit hit testing.
    func surfaceLayout(hasCompactContent: Bool, systemEventID: UUID?) -> HookySurfaceLayout {
        let compactWidth = notchWidth + (hideLeftMusicWing ? 56 : 112)

        if showScreenshotSuccess {
            return HookySurfaceLayout(
                mode: .screenshotSuccess,
                width: 66,
                height: notchHeight,
                horizontalOffset: -(notchWidth / 2 + 21),
                bottomLeadingRadius: 9,
                bottomTrailingRadius: 0
            )
        }

        if expanded {
            if screenshotPreview != nil {
                return HookySurfaceLayout(
                    mode: .screenshotPreview,
                    width: 380,
                    height: 250,
                    horizontalOffset: 0,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 18
                )
            }
            return HookySurfaceLayout(
                mode: .expanded,
                width: 440,
                height: 314,
                horizontalOffset: 0,
                bottomLeadingRadius: 18,
                bottomTrailingRadius: 18
            )
        }

        if let systemEventID {
            return HookySurfaceLayout(
                mode: .systemEvent(systemEventID),
                width: compactWidth,
                height: notchHeight + 46,
                horizontalOffset: hideLeftMusicWing ? 28 : 0,
                bottomLeadingRadius: 18,
                bottomTrailingRadius: 18
            )
        }

        if screenshotPreview != nil || hasCompactContent {
            return HookySurfaceLayout(
                mode: .compact,
                width: compactWidth,
                height: notchHeight,
                horizontalOffset: hideLeftMusicWing ? 28 : 0,
                bottomLeadingRadius: 9,
                bottomTrailingRadius: 9
            )
        }

        return HookySurfaceLayout(
            mode: .idle,
            width: max(140, notchWidth - 18),
            height: max(24, notchHeight - 3),
            horizontalOffset: 0,
            bottomLeadingRadius: 9,
            bottomTrailingRadius: 9
        )
    }
}
