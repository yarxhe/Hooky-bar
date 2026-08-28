import AppKit

/// Не активирует всё приложение при обычных кликах, но разрешает ввод в интерактивных полях.
final class HookyPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    /// Нативный Liquid Glass получает корректный active appearance только после
    /// того, как панель становится key. Флаг `.nonactivatingPanel` при этом не
    /// активирует Hooky bar целиком и не поднимает его как обычное приложение.
    func prepareForExpandedPresentation() {
        orderFrontRegardless()
        makeKey()
    }

    func finishExpandedPresentation() {
        if isKeyWindow { resignKey() }
    }
}
