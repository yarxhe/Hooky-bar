import AppKit
import ApplicationServices
import CoreBluetooth
import EventKit
import Foundation

protocol IntegrationDiagnosticsAdapter {
    func isApplicationInstalled(bundleIdentifier: String) -> Bool
    func authorization(for permission: IntegrationPermission) -> IntegrationAuthorizationState
    func isExecutableAvailable(at paths: [String]) -> Bool
    func openSystemSettings(for permission: IntegrationPermission)
}

/// Выполняет только read-only проверки. Диагностика никогда сама не вызывает
/// системный prompt и не получает доступ от имени пользователя.
struct SystemIntegrationDiagnosticsAdapter: IntegrationDiagnosticsAdapter {
    func isApplicationInstalled(bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    func authorization(for permission: IntegrationPermission) -> IntegrationAuthorizationState {
        switch permission {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notDetermined
        case .calendar:
            return calendarAuthorization
        case .bluetooth:
            return bluetoothAuthorization
        case .desktopFolder:
            return directoryAuthorization(for: screenshotFolder)
        case .downloadsFolder:
            guard let folder = FileManager.default.urls(
                for: .downloadsDirectory,
                in: .userDomainMask
            ).first else { return .unavailable }
            return directoryAuthorization(for: folder)
        case .automation:
            // Без отправки Apple Event macOS не даёт надёжно определить доступ.
            return .notDetermined
        case .localNetwork:
            // Яндекс использует только loopback 127.0.0.1 и не требует prompt.
            return .granted
        }
    }

    func isExecutableAvailable(at paths: [String]) -> Bool {
        paths.contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func openSystemSettings(for permission: IntegrationPermission) {
        let anchor: String
        switch permission {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .automation: anchor = "Privacy_Automation"
        case .bluetooth: anchor = "Privacy_Bluetooth"
        case .calendar: anchor = "Privacy_Calendars"
        case .desktopFolder, .downloadsFolder: anchor = "Privacy_FilesAndFolders"
        case .localNetwork: anchor = "Privacy_LocalNetwork"
        }
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private var calendarAuthorization: IntegrationAuthorizationState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .writeOnly, .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .unavailable
        }
    }

    private var bluetoothAuthorization: IntegrationAuthorizationState {
        switch CBManager.authorization {
        case .allowedAlways: .granted
        case .denied: .denied
        case .restricted: .restricted
        case .notDetermined: .notDetermined
        @unknown default: .unavailable
        }
    }

    private func directoryAuthorization(for folder: URL) -> IntegrationAuthorizationState {
        do {
            _ = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            return .granted
        } catch CocoaError.fileReadNoPermission {
            return .denied
        } catch {
            return FileManager.default.fileExists(atPath: folder.path) ? .restricted : .unavailable
        }
    }

    private var screenshotFolder: URL {
        let configured = UserDefaults.standard
            .persistentDomain(forName: "com.apple.screencapture")?["location"] as? String
        return configured.map {
            URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath)
        } ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }
}
