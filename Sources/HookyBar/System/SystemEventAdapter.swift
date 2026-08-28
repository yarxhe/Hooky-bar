import Foundation

/// Общий внутренний контракт для событий macOS. Адаптер знает системный API,
/// а store отвечает только за включение, очередь и показ события.
protocol SystemEventAdapter: AnyObject {
    var kind: HookySystemEvent.Kind { get }
    var capability: IntegrationCapabilityDeclaration { get }

    func start(receive: @escaping (HookySystemEvent) -> Void)
    func stop()
}
