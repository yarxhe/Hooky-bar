import Foundation

struct ClipboardAdapterUpdate {
    let sourceID: String
    let items: [ClipboardItem]
    let insertedItem: ClipboardItem?
}

/// Внутренняя точка расширения Hooky bar. Будущий SDK сможет обернуть внешний provider в этот протокол.
protocol ClipboardSourceAdapter: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var capability: IntegrationCapabilityDeclaration { get }

    func start(receive: @escaping (ClipboardAdapterUpdate) -> Void)
    func stop()
    func copy(_ item: ClipboardItem) -> IntegrationResult
    func remove(_ item: ClipboardItem) -> IntegrationResult
    func remove(_ items: [ClipboardItem]) -> IntegrationResult
}

extension ClipboardSourceAdapter {
    func remove(_ items: [ClipboardItem]) -> IntegrationResult {
        for item in items {
            let result = remove(item)
            if !result.succeeded { return result }
        }
        return .success
    }
}
