import Darwin
import Foundation
import OSLog

enum HookyDiagnostics {
    private static let controlsLogger = Logger(subsystem: "com.yarxhe.HookyBar", category: "controls")
    private static let bridgeLogger = Logger(subsystem: "com.yarxhe.HookyBar", category: "yandex-bridge")
    private static let memoryLogger = Logger(subsystem: "com.yarxhe.HookyBar", category: "memory")

    static func control(_ event: String) {
        controlsLogger.notice("\(decorated(event), privacy: .public)")
    }

    static func bridge(_ event: String, isError: Bool = false) {
        let message = decorated(event)
        if isError {
            bridgeLogger.error("\(message, privacy: .public)")
        } else {
            bridgeLogger.notice("\(message, privacy: .public)")
        }
    }

    static func memory(_ event: String) {
        memoryLogger.notice("\(decorated(event), privacy: .public)")
    }

    static var footprintMegabytes: Double? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.phys_footprint) / 1_048_576
    }

    private static func decorated(_ event: String) -> String {
        guard let footprintMegabytes else { return event }
        return "\(event) footprint_mb=\(String(format: "%.2f", footprintMegabytes))"
    }
}
