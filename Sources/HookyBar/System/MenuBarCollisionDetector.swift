import AppKit
import ApplicationServices

enum MenuBarCollisionDetector {
    static let maximumWingWidth: CGFloat = 56
    private static let safetyGap: CGFloat = 10
    private static let minimumVisibleWingWidth: CGFloat = 32

    struct CompactWingWidths: Equatable {
        let leading: CGFloat
        let trailing: CGFloat
    }

    static func compactWingWidths(notchLeft: CGFloat, notchRight: CGFloat) -> CompactWingWidths {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return CompactWingWidths(leading: maximumWingWidth, trailing: maximumWingWidth)
        }
        let edges = menuEdges(of: app, notchLeft: notchLeft, notchRight: notchRight)
        return compactWingWidths(
            notchLeft: notchLeft,
            notchRight: notchRight,
            leadingOccupiedEdge: edges.leading,
            trailingOccupiedEdge: edges.trailing
        )
    }

    static func compactWingWidths(
        notchLeft: CGFloat,
        notchRight: CGFloat,
        leadingOccupiedEdge: CGFloat?,
        trailingOccupiedEdge: CGFloat?
    ) -> CompactWingWidths {
        let leadingClearance = leadingOccupiedEdge.map { notchLeft - $0 }
        let trailingClearance = trailingOccupiedEdge.map { $0 - notchRight }
        return CompactWingWidths(
            leading: wingWidth(for: leadingClearance),
            trailing: wingWidth(for: trailingClearance)
        )
    }

    private static func wingWidth(for clearance: CGFloat?) -> CGFloat {
        guard let clearance else { return maximumWingWidth }
        let available = min(maximumWingWidth, clearance - safetyGap)
        guard available >= minimumVisibleWingWidth else { return 0 }
        return available
    }

    private static func menuEdges(
        of app: NSRunningApplication,
        notchLeft: CGFloat,
        notchRight: CGFloat
    ) -> (leading: CGFloat?, trailing: CGFloat?) {
        guard AXIsProcessTrusted() else { return (nil, nil) }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var menuValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuValue) == .success,
              let menuValue else { return (nil, nil) }
        let menuBar = unsafeBitCast(menuValue, to: AXUIElement.self)
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return (nil, nil) }
        var leading: CGFloat?
        var trailing: CGFloat?
        for item in children {
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue) == .success,
                  let positionValue, let sizeValue else { continue }
            var position = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position),
                  AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size) else { continue }
            let frame = CGRect(origin: position, size: size)
            if frame.minX < notchLeft {
                leading = max(leading ?? -.infinity, frame.maxX)
            }
            if frame.maxX > notchRight {
                trailing = min(trailing ?? .infinity, frame.minX)
            }
        }
        return (leading, trailing)
    }
}
