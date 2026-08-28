import SwiftUI

private struct HookyGlassRevisionKey: EnvironmentKey {
    static let defaultValue: UInt = 0
}

private extension EnvironmentValues {
    var hookyGlassRevision: UInt {
        get { self[HookyGlassRevisionKey.self] }
        set { self[HookyGlassRevisionKey.self] = newValue }
    }
}

/// Единая точка входа для системного Liquid Glass.
/// На macOS 26 и новее SwiftUI рисует настоящий Glass, на старых системах
/// остаётся лёгкий material-fallback без изменения геометрии элементов.
private struct HookyGlassModifier: ViewModifier {
    @Environment(\.hookyGlassRevision) private var revision

    let cornerRadius: CGFloat
    let interactive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(
                .regular.tint(HookyTheme.glassTint).interactive(interactive),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            // После долгого простоя compositor иногда сохраняет неактивный snapshot
            // прозрачной NSPanel. Новая identity пересоздаёт только glass-layer,
            // не сбрасывая состояние всего экрана.
            .id(revision)
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .background(
                    HookyTheme.glassFallbackFill,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(HookyTheme.glassFallbackStroke, lineWidth: 0.8)
                }
        }
    }
}

/// Собирает все стеклянные формы открытой панели в один нативный render pass.
struct HookyGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

extension View {
    /// Применяет нативное стекло только там, где оно участвует в иерархии интерфейса.
    @ViewBuilder
    func hookyGlass(
        enabled: Bool = true,
        cornerRadius: CGFloat,
        interactive: Bool = false
    ) -> some View {
        if enabled {
            modifier(HookyGlassModifier(
                cornerRadius: cornerRadius,
                interactive: interactive
            ))
        } else {
            self
        }
    }

    /// Обновляет identity нативных glass-layer при новом раскрытии панели.
    func hookyGlassRevision(_ revision: UInt) -> some View {
        environment(\.hookyGlassRevision, revision)
    }
}
