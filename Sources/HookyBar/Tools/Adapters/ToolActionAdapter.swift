import Foundation

/// Общий контракт для встроенных инструментов и будущих SDK-адаптеров.
protocol ToolActionAdapter {
    var supportedActions: Set<ToolAction> { get }
    var capability: IntegrationCapabilityDeclaration { get }
    func perform(_ action: ToolAction) -> IntegrationResult
}
