import Foundation

enum IntegrationAuthorizationState: Equatable {
    case granted
    case denied
    case notDetermined
    case restricted
    case unavailable
}

enum IntegrationDiagnosticStatus: Equatable {
    case ready
    case needsAttention
    case unavailable
    case inactive
    case checkedOnUse

    var title: String {
        switch self {
        case .ready: L10n.tr("settings.diagnostics.status.ready")
        case .needsAttention: L10n.tr("settings.diagnostics.status.attention")
        case .unavailable: L10n.tr("settings.diagnostics.status.unavailable")
        case .inactive: L10n.tr("settings.diagnostics.status.inactive")
        case .checkedOnUse: L10n.tr("settings.diagnostics.status.onUse")
        }
    }
}

struct IntegrationDiagnosticItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let status: IntegrationDiagnosticStatus
    let settingsPermission: IntegrationPermission?
}

struct IntegrationDiagnosticsContext {
    let musicSource: MusicSource
    let musicInstalled: Bool
    let musicRunning: Bool
    let musicControlChannelAvailable: Bool?
    let notesApp: NotesApp
    let notesInstalled: Bool
    let accessibility: IntegrationAuthorizationState
    let calendar: IntegrationAuthorizationState
    let bluetooth: IntegrationAuthorizationState
    let screenshotsFolder: IntegrationAuthorizationState
    let downloadsFolder: IntegrationAuthorizationState
    let calendarEnabled: Bool
    let bluetoothEnabled: Bool
    let airDropEnabled: Bool
    let developerModeEnabled: Bool
    let selectedIDE: DeveloperIDE
    let selectedIDEInstalled: Bool
    let githubCLIAvailable: Bool
}

enum IntegrationDiagnosticsBuilder {
    static func makeItems(from context: IntegrationDiagnosticsContext) -> [IntegrationDiagnosticItem] {
        var items = [
            applicationItem(
                id: "music.application",
                title: context.musicSource.fullTitle,
                symbol: context.musicSource.fallbackSymbol,
                installed: context.musicInstalled,
                running: context.musicRunning
            )
        ]

        if context.musicSource == .yandex {
            items.append(yandexControlItem(context: context))
        }

        if context.musicSource != .yandex || context.notesApp == .appleNotes {
            items.append(IntegrationDiagnosticItem(
                id: "system.automation",
                title: L10n.tr("settings.diagnostics.automation.title"),
                detail: L10n.tr("settings.diagnostics.automation.onUse"),
                symbol: "apple.logo",
                status: .checkedOnUse,
                settingsPermission: .automation
            ))
        }

        items.append(applicationItem(
            id: "notes.application",
            title: context.notesApp.title,
            symbol: context.notesApp.symbol,
            installed: context.notesInstalled,
            running: nil
        ))

        items.append(permissionItem(
            id: "clipboard.screenshots",
            title: L10n.tr("settings.diagnostics.screenshots.title"),
            symbol: "photo.on.rectangle.angled",
            permission: .desktopFolder,
            authorization: context.screenshotsFolder,
            grantedDetail: L10n.tr("settings.diagnostics.screenshots.ready")
        ))

        items.append(featurePermissionItem(
            id: "system.calendar",
            title: L10n.tr("settings.calendar.title"),
            symbol: "calendar",
            permission: .calendar,
            enabled: context.calendarEnabled,
            authorization: context.calendar
        ))
        items.append(featurePermissionItem(
            id: "system.bluetooth",
            title: L10n.tr("settings.bluetooth.title"),
            symbol: "antenna.radiowaves.left.and.right",
            permission: .bluetooth,
            enabled: context.bluetoothEnabled,
            authorization: context.bluetooth
        ))
        items.append(featurePermissionItem(
            id: "system.airdrop",
            title: L10n.tr("settings.airdrop.title"),
            symbol: "airdrop",
            permission: .downloadsFolder,
            enabled: context.airDropEnabled,
            authorization: context.downloadsFolder
        ))

        if context.developerModeEnabled {
            items.append(applicationItem(
                id: "developer.ide",
                title: context.selectedIDE.title,
                symbol: context.selectedIDE.symbol,
                installed: context.selectedIDEInstalled,
                running: nil
            ))
            items.append(IntegrationDiagnosticItem(
                id: "developer.githubCLI",
                title: "GitHub CLI",
                detail: context.githubCLIAvailable
                    ? L10n.tr("settings.diagnostics.github.ready")
                    : L10n.tr("settings.diagnostics.github.missing"),
                symbol: "point.3.connected.trianglepath.dotted",
                status: context.githubCLIAvailable ? .ready : .unavailable,
                settingsPermission: nil
            ))
        }

        return items
    }

    private static func applicationItem(
        id: String,
        title: String,
        symbol: String,
        installed: Bool,
        running: Bool?
    ) -> IntegrationDiagnosticItem {
        let status: IntegrationDiagnosticStatus
        let detail: String
        if !installed {
            status = .unavailable
            detail = L10n.tr("settings.diagnostics.application.missing")
        } else if running == false {
            status = .inactive
            detail = L10n.tr("settings.diagnostics.application.closed")
        } else if running == true {
            status = .ready
            detail = L10n.tr("settings.diagnostics.application.running")
        } else {
            status = .ready
            detail = L10n.tr("settings.diagnostics.application.installed")
        }
        return IntegrationDiagnosticItem(
            id: id,
            title: title,
            detail: detail,
            symbol: symbol,
            status: status,
            settingsPermission: nil
        )
    }

    private static func yandexControlItem(
        context: IntegrationDiagnosticsContext
    ) -> IntegrationDiagnosticItem {
        if !context.musicInstalled {
            return IntegrationDiagnosticItem(
                id: "music.yandex.controls",
                title: L10n.tr("settings.diagnostics.yandex.title"),
                detail: L10n.tr("settings.diagnostics.application.missing"),
                symbol: "hand.raised.fill",
                status: .unavailable,
                settingsPermission: nil
            )
        }
        if !context.musicRunning {
            return IntegrationDiagnosticItem(
                id: "music.yandex.controls",
                title: L10n.tr("settings.diagnostics.yandex.title"),
                detail: L10n.tr("settings.diagnostics.yandex.waiting"),
                symbol: "hand.raised.fill",
                status: .inactive,
                settingsPermission: nil
            )
        }
        if context.musicControlChannelAvailable == true {
            return IntegrationDiagnosticItem(
                id: "music.yandex.controls",
                title: L10n.tr("settings.diagnostics.yandex.title"),
                detail: L10n.tr("settings.diagnostics.yandex.ready"),
                symbol: "hand.raised.fill",
                status: .ready,
                settingsPermission: nil
            )
        }
        return permissionItem(
            id: "music.yandex.controls",
            title: L10n.tr("settings.diagnostics.yandex.title"),
            symbol: "hand.raised.fill",
            permission: .accessibility,
            authorization: context.accessibility,
            grantedDetail: L10n.tr("settings.diagnostics.yandex.ready"),
            pendingDetail: L10n.tr("settings.diagnostics.yandex.optional")
        )
    }

    private static func featurePermissionItem(
        id: String,
        title: String,
        symbol: String,
        permission: IntegrationPermission,
        enabled: Bool,
        authorization: IntegrationAuthorizationState
    ) -> IntegrationDiagnosticItem {
        guard enabled else {
            return IntegrationDiagnosticItem(
                id: id,
                title: title,
                detail: L10n.tr("settings.diagnostics.feature.disabled"),
                symbol: symbol,
                status: .inactive,
                settingsPermission: nil
            )
        }
        return permissionItem(
            id: id,
            title: title,
            symbol: symbol,
            permission: permission,
            authorization: authorization,
            grantedDetail: L10n.tr("settings.diagnostics.feature.ready")
        )
    }

    private static func permissionItem(
        id: String,
        title: String,
        symbol: String,
        permission: IntegrationPermission,
        authorization: IntegrationAuthorizationState,
        grantedDetail: String,
        pendingDetail: String? = nil
    ) -> IntegrationDiagnosticItem {
        let status: IntegrationDiagnosticStatus
        let detail: String
        switch authorization {
        case .granted:
            status = .ready
            detail = grantedDetail
        case .notDetermined:
            status = .checkedOnUse
            detail = pendingDetail ?? L10n.tr("settings.diagnostics.permission.notDetermined")
        case .denied:
            status = .needsAttention
            detail = L10n.tr("settings.diagnostics.permission.denied")
        case .restricted:
            status = .needsAttention
            detail = L10n.tr("settings.diagnostics.permission.restricted")
        case .unavailable:
            status = .unavailable
            detail = L10n.tr("settings.diagnostics.permission.unavailable")
        }
        return IntegrationDiagnosticItem(
            id: id,
            title: title,
            detail: detail,
            symbol: symbol,
            status: status,
            settingsPermission: status == .ready ? nil : permission
        )
    }
}
