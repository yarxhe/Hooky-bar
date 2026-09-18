import Darwin
import Foundation

public struct NativeProcessUsage {
    public let reading: UsageReading
    public let processStart: UInt64

    public static func machSeconds(_ ticks: UInt64, numerator: UInt32, denominator: UInt32) -> Double {
        // Convert in floating point: multiplying the full UInt64 tick count can
        // overflow on long-lived processes. A Mach tick is not necessarily 1 ns.
        Double(ticks) * Double(numerator) / Double(denominator) / 1e9
    }

    public static func read(pid: pid_t) throws -> Self {
        var usage = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ESRCH) }
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0 else {
            throw POSIXError(.EINVAL)
        }
        let cpu = machSeconds(usage.ri_user_time, numerator: timebase.numer, denominator: timebase.denom)
            + machSeconds(usage.ri_system_time, numerator: timebase.numer, denominator: timebase.denom)
        return Self(reading: UsageReading(time: ProcessInfo.processInfo.systemUptime,
                                          cpuSeconds: cpu, footprintBytes: usage.ri_phys_footprint),
                    processStart: usage.ri_proc_start_abstime)
    }
}
