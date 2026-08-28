import AppKit

struct SystemToolAdapter: ToolActionAdapter {
    let supportedActions: Set<ToolAction> = [.openCalendar, .openDownloads]
    let capability = IntegrationCapabilityDeclaration(
        id: "utilities.system",
        permissions: [.downloadsFolder]
    )

    func perform(_ action: ToolAction) -> IntegrationResult {
        switch action {
        case .openCalendar:
            return NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
                ? .success : .failed(.commandRejected)
        case .openDownloads:
            guard let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else {
                return .failed(.unavailable)
            }
            return NSWorkspace.shared.open(downloads) ? .success : .failed(.permissionDenied(.downloadsFolder))
        default:
            return .failed(.unsupported)
        }
    }
}
