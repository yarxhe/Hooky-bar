import Foundation

enum IntegrationDiagnosticsReportBuilder {
    static func makeReport(
        items: [IntegrationDiagnosticItem],
        appVersion: String,
        operatingSystem: String,
        generatedAt: Date = Date()
    ) -> String {
        let timestamp = ISO8601DateFormatter().string(from: generatedAt)
        let integrations = items.map { item in
            "- [\(item.status.reportValue)] \(singleLine(item.title)) — \(singleLine(item.detail))"
        }

        return ([
            "Hooky bar diagnostics",
            "App: \(singleLine(appVersion))",
            "macOS: \(singleLine(operatingSystem))",
            "Generated: \(timestamp)",
            "",
            "Integrations:"
        ] + integrations).joined(separator: "\n")
    }

    private static func singleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

private extension IntegrationDiagnosticStatus {
    var reportValue: String {
        switch self {
        case .ready: "ready"
        case .needsAttention: "needs-attention"
        case .unavailable: "unavailable"
        case .inactive: "inactive"
        case .checkedOnUse: "checked-on-use"
        }
    }
}
