import Foundation

/// Системные доступы, которые встроенная или будущая интеграция может запросить.
enum IntegrationPermission: String, Codable, CaseIterable, Sendable {
    case automation
    case accessibility
    case bluetooth
    case calendar
    case desktopFolder
    case downloadsFolder
    case localNetwork
}

/// Машинно-читаемое описание интеграции для настроек, диагностики и будущего SDK.
struct IntegrationCapabilityDeclaration: Equatable, Sendable {
    let id: String
    let permissions: Set<IntegrationPermission>
    let isOptional: Bool

    init(
        id: String,
        permissions: Set<IntegrationPermission> = [],
        isOptional: Bool = true
    ) {
        self.id = id
        self.permissions = permissions
        self.isOptional = isOptional
    }
}

enum IntegrationFailure: Error, Equatable, Sendable {
    case notInstalled
    case unavailable
    case permissionDenied(IntegrationPermission)
    case unsupported
    case staleData
    case commandRejected
    case invalidConfiguration
}

struct IntegrationResult: Equatable, Sendable {
    let failure: IntegrationFailure?

    var succeeded: Bool { failure == nil }

    static let success = IntegrationResult(failure: nil)

    static func failed(_ failure: IntegrationFailure) -> IntegrationResult {
        IntegrationResult(failure: failure)
    }
}
