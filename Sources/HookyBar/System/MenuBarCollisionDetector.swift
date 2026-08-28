import AppKit
import ApplicationServices

enum MenuBarCollisionDetector {
    static func shouldHideLeftWing(notchLeft: CGFloat) -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        if let edge = rightmostMenuEdge(of: app, before: notchLeft) {
            return edge > notchLeft - 10
        }
        return false
    }

    private static func rightmostMenuEdge(of app: NSRunningApplication, before notchLeft: CGFloat) -> CGFloat? {
        guard AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var menuValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuValue) == .success,
              let menuValue else { return nil }
        let menuBar = unsafeBitCast(menuValue, to: AXUIElement.self)
        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(menuBar, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else { return nil }
        return children.reduce(CGFloat.zero) { partial, item in
            var positionValue: CFTypeRef?
            var sizeValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue) == .success,
                  let positionValue, let sizeValue else { return partial }
            var position = CGPoint.zero
            var size = CGSize.zero
            guard AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position),
                  AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size) else { return partial }
            // AXMenuBar may also expose right-side status extras. They are not
            // part of the active app's menu and must not hide the left wing.
            guard position.x < notchLeft else { return partial }
            return max(partial, position.x + size.width)
        }
    }
}
