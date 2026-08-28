import AppKit
import IOBluetooth

final class BluetoothEventAdapter: NSObject, SystemEventAdapter {
    let kind: HookySystemEvent.Kind = .bluetooth
    let capability = IntegrationCapabilityDeclaration(
        id: "system.bluetooth",
        permissions: [.bluetooth]
    )

    private var receive: ((HookySystemEvent) -> Void)?
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]
    private var knownConnections = Set<String>()

    func start(receive: @escaping (HookySystemEvent) -> Void) {
        self.receive = receive
        guard connectNotification == nil else { return }
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?
            .filter { $0.isConnected() }
            .forEach {
                knownConnections.insert(identity($0))
                registerDisconnectNotification($0)
            }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:))
        )
    }

    func stop() {
        connectNotification?.unregister()
        connectNotification = nil
        disconnectNotifications.values.forEach { $0.unregister() }
        disconnectNotifications.removeAll()
        knownConnections.removeAll()
        receive = nil
    }

    @objc private func deviceConnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        guard knownConnections.insert(identity(device)).inserted else { return }
        registerDisconnectNotification(device)
        let name = device.name ?? L10n.tr("event.bluetooth.device")
        receive?(HookySystemEvent(
            kind: .bluetooth,
            title: name,
            subtitle: L10n.tr("event.connected"),
            symbol: symbol(for: name),
            tint: .systemBlue,
            deduplicationKey: "bt-connect-\(device.addressString ?? name)"
        ))
    }

    @objc private func deviceDisconnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        guard knownConnections.remove(identity(device)) != nil else { return }
        let name = device.name ?? L10n.tr("event.bluetooth.device")
        if let address = device.addressString {
            disconnectNotifications.removeValue(forKey: address)?.unregister()
        }
        receive?(HookySystemEvent(
            kind: .bluetooth,
            title: name,
            subtitle: L10n.tr("event.disconnected"),
            symbol: symbol(for: name),
            tint: .systemGray,
            deduplicationKey: "bt-disconnect-\(device.addressString ?? name)"
        ))
    }

    private func registerDisconnectNotification(_ device: IOBluetoothDevice) {
        guard let address = device.addressString, disconnectNotifications[address] == nil else { return }
        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:device:))
        )
    }

    private func identity(_ device: IOBluetoothDevice) -> String {
        device.addressString ?? device.name ?? "unknown-bluetooth-device"
    }

    private func symbol(for name: String) -> String {
        let normalized = name.lowercased()
        if normalized.contains("airpod") { return "airpodspro" }
        if normalized.contains("head") || normalized.contains("buds") || normalized.contains("науш") { return "headphones" }
        if normalized.contains("keyboard") || normalized.contains("клав") { return "keyboard.fill" }
        if normalized.contains("mouse") || normalized.contains("мыш") { return "computermouse.fill" }
        if normalized.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if normalized.contains("controller") || normalized.contains("gamepad") || normalized.contains("dual") { return "gamecontroller.fill" }
        return "antenna.radiowaves.left.and.right.circle.fill"
    }
}
