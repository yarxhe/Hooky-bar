import AppKit

/// Не активирует всё приложение при обычных кликах, но разрешает ввод в интерактивных полях.
final class HookyPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Keyboard focus for native fields without activating the whole app.
    /// `.nonactivatingPanel` keeps the foreground application's activation state.
    func prepareForExpandedPresentation() {
        orderFrontRegardless()
        makeKey()
    }

    func finishExpandedPresentation() {
        if isKeyWindow { resignKey() }
    }
}
