import Darwin
import Foundation
import OSLog

enum HookyDiagnostics {
    private struct Configuration: Decodable {
        let debugLogging: Bool
    }

    private static let controlsLogger = Logger(subsystem: "com.yarxhe.HookyBar", category: "controls")
    private static let bridgeLogger = Logger(subsystem: "com.yarxhe.HookyBar", category: "yandex-bridge")
    private static let memoryLogger = Logger(subsystem: "com.yarxhe.HookyBar", category: "memory")
    private static let configuration = DebugLoggingConfiguration()
    private static let processUsage = ProcessUsageSampler()

    static var configurationURL: URL { configuration.url }
    static var isEnabled: Bool { configuration.isEnabled }

    static func bootstrap() {
        configuration.ensureFileExists()
    }

    static func control(_ event: String) {
        guard isEnabled else { return }
        controlsLogger.notice("\(decorated(event), privacy: .public)")
    }

    static func bridge(_ event: String, isError: Bool = false) {
        guard isEnabled else { return }
        let message = decorated(event)
        if isError {
            bridgeLogger.error("\(message, privacy: .public)")
        } else {
            bridgeLogger.notice("\(message, privacy: .public)")
        }
    }

    static func memory(_ event: String) {
        guard isEnabled else { processUsage.reset(); return }
        let usage = processUsage.sample()
        memoryLogger.notice("\(decorated(event) + usage, privacy: .public)")
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

    private final class ProcessUsageSampler {
        private let lock = NSLock()
        private var previous: ProcessCPUReading?

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            previous = nil
        }

        func sample() -> String {
            var usage = rusage()
            guard getrusage(RUSAGE_SELF, &usage) == 0 else { return "" }
            let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
            let current = ProcessCPUReading(uptime: ProcessInfo.processInfo.systemUptime, cpuSeconds: cpu)
            lock.lock()
            defer { previous = current; lock.unlock() }
            guard let previous, let percent = current.percent(since: previous) else { return "" }
            return " cpu_percent=\(String(format: "%.2f", percent)) cpu_interval_s=\(String(format: "%.1f", current.uptime - previous.uptime))"
        }
    }

    private final class DebugLoggingConfiguration {
        let url: URL

        private let lock = NSLock()
        private var enabled = false
        private var lastRead = Date.distantPast

        init(fileManager: FileManager = .default) {
            let applicationSupport = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.homeDirectoryForCurrentUser
            url = applicationSupport
                .appendingPathComponent("Hooky bar", isDirectory: true)
                .appendingPathComponent("config.json", isDirectory: false)
        }

        var isEnabled: Bool {
            lock.lock()
            defer { lock.unlock() }
            guard Date().timeIntervalSince(lastRead) >= 1 else { return enabled }
            lastRead = Date()
            guard let data = try? Data(contentsOf: url),
                  let value = try? JSONDecoder().decode(Configuration.self, from: data) else {
                enabled = false
                return false
            }
            enabled = value.debugLogging
            return enabled
        }

        func ensureFileExists(fileManager: FileManager = .default) {
            lock.lock()
            defer { lock.unlock() }
            guard !fileManager.fileExists(atPath: url.path) else { return }
            do {
                try fileManager.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("{\n  \"debugLogging\": false\n}\n".utf8).write(to: url, options: .atomic)
            } catch {
                enabled = false
            }
        }
    }
}

/// Like Activity Monitor: 100% means one fully occupied CPU core. Do not clamp
/// multicore use to 100%; this is an interval average, not an instantaneous peak.
struct ProcessCPUReading {
    let uptime: TimeInterval
    let cpuSeconds: TimeInterval

    func percent(since previous: Self) -> Double? {
        let elapsed = uptime - previous.uptime
        let used = cpuSeconds - previous.cpuSeconds
        guard elapsed > 0, used >= 0 else { return nil }
        return used / elapsed * 100
    }
}
