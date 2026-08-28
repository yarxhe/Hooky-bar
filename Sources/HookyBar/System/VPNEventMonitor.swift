import AppKit
import Darwin
import Network
import SystemConfiguration

final class VPNEventAdapter: SystemEventAdapter, @unchecked Sendable {
    let kind: HookySystemEvent.Kind = .vpn
    let capability = IntegrationCapabilityDeclaration(id: "system.vpn")

    private var receive: ((HookySystemEvent) -> Void)?
    private var pathMonitor: NWPathMonitor?
    private var fallbackTimer: Timer?
    private let monitorQueue = DispatchQueue(label: "com.yarxhe.HookyBar.vpn-path", qos: .utility)
    private var knownServices: [String: String] = [:]
    private var knownTunnels = Set<String>()
    private var didLoadState = false

    func start(receive: @escaping (HookySystemEvent) -> Void) {
        self.receive = receive
        guard pathMonitor == nil else { return }
        refresh()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        pathMonitor = monitor
        monitor.start(queue: monitorQueue)

        // Некоторые VPN-клиенты не меняют NWPath при переключении туннеля.
        // Редкая страховочная проверка сохраняет поддержку таких провайдеров,
        // не будя приложение каждые три секунды в обычном режиме.
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        knownServices.removeAll()
        knownTunnels.removeAll()
        didLoadState = false
        receive = nil
    }

    private func refresh() {
        let current = connectedServices()
        let currentTunnels = activeTunnelInterfaces()
        if didLoadState {
            let connected = current.filter { knownServices[$0.key] == nil }
            let disconnected = knownServices.filter { current[$0.key] == nil }
            connected.forEach { id, name in
                emit(title: name, subtitle: L10n.tr("event.vpn.connected"), symbol: "checkmark.shield.fill",
                     tint: .systemGreen, key: "vpn-on-\(id)")
            }
            disconnected.forEach { id, name in
                emit(title: name, subtitle: L10n.tr("event.vpn.disconnected"), symbol: "xmark.shield.fill",
                     tint: .systemOrange, key: "vpn-off-\(id)")
            }
            if connected.isEmpty, !currentTunnels.subtracting(knownTunnels).isEmpty {
                emit(title: "VPN", subtitle: L10n.tr("event.vpn.tunnelConnected"), symbol: "checkmark.shield.fill",
                     tint: .systemGreen, key: "vpn-tunnel-on")
            }
            if disconnected.isEmpty, !knownTunnels.subtracting(currentTunnels).isEmpty {
                emit(title: "VPN", subtitle: L10n.tr("event.vpn.tunnelDisconnected"), symbol: "xmark.shield.fill",
                     tint: .systemOrange, key: "vpn-tunnel-off")
            }
        }
        knownServices = current
        knownTunnels = currentTunnels
        didLoadState = true
    }

    private func emit(title: String, subtitle: String, symbol: String, tint: NSColor, key: String) {
        receive?(HookySystemEvent(
            kind: .vpn,
            title: title,
            subtitle: subtitle,
            symbol: symbol,
            tint: tint,
            deduplicationKey: key
        ))
    }

    private func activeTunnelInterfaces() -> Set<String> {
        var firstAddress: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&firstAddress) == 0, let firstAddress else { return [] }
        defer { freeifaddrs(firstAddress) }
        var result = Set<String>()
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let current = cursor {
            let interface = current.pointee
            if let namePointer = interface.ifa_name,
               let address = interface.ifa_addr,
               (address.pointee.sa_family == UInt8(AF_INET) || address.pointee.sa_family == UInt8(AF_INET6)),
               (interface.ifa_flags & UInt32(IFF_UP)) != 0 {
                let name = String(cString: namePointer)
                if name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec") {
                    result.insert(name)
                }
            }
            cursor = interface.ifa_next
        }
        return result
    }

    private func connectedServices() -> [String: String] {
        guard let preferences = SCPreferencesCreate(nil, "Hooky bar" as CFString, nil),
              let set = SCNetworkSetCopyCurrent(preferences),
              let services = SCNetworkSetCopyServices(set) as? [SCNetworkService] else { return [:] }
        let supportedTypes = [kSCNetworkInterfaceTypePPP, kSCNetworkInterfaceTypeIPSec, kSCNetworkInterfaceTypeL2TP]
            .map { $0 as String }
        var result: [String: String] = [:]
        for service in services {
            guard let interface = SCNetworkServiceGetInterface(service),
                  let type = SCNetworkInterfaceGetInterfaceType(interface) as String?,
                  supportedTypes.contains(type),
                  let identifier = SCNetworkServiceGetServiceID(service) as String?,
                  let connection = SCNetworkConnectionCreateWithServiceID(nil, identifier as CFString, nil, nil),
                  SCNetworkConnectionGetStatus(connection) == .connected else { continue }
            result[identifier] = (SCNetworkServiceGetName(service) as String?) ?? "VPN"
        }
        return result
    }
}
