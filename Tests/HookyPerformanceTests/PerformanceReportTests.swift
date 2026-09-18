import Testing
import Foundation
import Darwin
@testable import HookyPerformanceSupport

struct PerformanceReportTests {
    private func sample(cpu: Double, duration: Double = 1, memory: Double = 50,
                        phase: String = "tabs", cycle: Int = 0) -> UsageSample {
        UsageSample(time: 1, duration: duration, cpuPercent: cpu, footprintMB: memory, phase: phase, cycle: cycle)
    }

    @Test func cpuUsesProcessTimeAndIsNotClampedToOneCore() {
        let start = UsageReading(time: 1, cpuSeconds: 1, footprintBytes: 0)
        let end = UsageReading(time: 2, cpuSeconds: 2.5, footprintBytes: 52_428_800)
        let result = end.interval(since: start, phase: "open", cycle: 0)
        #expect(result?.cpuPercent == 150)
        #expect(result?.footprintMB == 50)
        #expect(start.interval(since: end, phase: "open", cycle: 0) == nil)
        #expect(start.interval(since: start, phase: "open", cycle: 0) == nil)
    }

    @Test func machTicksAreConvertedForBothAppleSiliconAndIntel() {
        #expect(NativeProcessUsage.machSeconds(24_000_000, numerator: 125, denominator: 3) == 1)
        #expect(NativeProcessUsage.machSeconds(1_000_000_000, numerator: 1, denominator: 1) == 1)
    }

    @Test func nativeCPUReaderMatchesIndependentGetrusage() throws {
        func referenceCPU() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
        }
        let referenceBefore = referenceCPU()
        let before = try NativeProcessUsage.read(pid: getpid())
        let deadline = ProcessInfo.processInfo.systemUptime + 0.15
        var checksum: UInt64 = 1
        repeat {
            for index in 0..<10_000 { checksum = checksum &* 1_664_525 &+ UInt64(index) &+ 1_013_904_223 }
        } while ProcessInfo.processInfo.systemUptime < deadline
        let after = try NativeProcessUsage.read(pid: getpid())
        let referenceDelta = referenceCPU() - referenceBefore
        let measuredDelta = after.reading.cpuSeconds - before.reading.cpuSeconds
        #expect(checksum != 0)
        #expect(before.processStart == after.processStart)
        #expect(referenceDelta > 0.01)
        #expect(abs(measuredDelta - referenceDelta) < max(0.008, referenceDelta * 0.1))
    }

    @Test func averageIsTimeWeightedAndEmptyIsNotZero() {
        let summary = PhaseSummary([sample(cpu: 50), sample(cpu: 0, duration: 3)])
        #expect(summary?.meanCPU == 12.5)
        #expect(summary?.peakCPU == 50)
        #expect(PhaseSummary([]) == nil)
    }

    @Test func warmupAndTransientPeaksDoNotMasqueradeAsRetainedMemory() {
        var report = fixture()
        report.samples.append(sample(cpu: 500, memory: 900, phase: "tabs", cycle: -1))
        report.samples.append(sample(cpu: 10, memory: 300, phase: "tabs"))
        #expect(report.phases["tabs"]?.peakCPU == 20)
        #expect(report.phases["tabs"]?.peakFootprintMB == 300)
        #expect(report.retainedMB == 2)
        #expect(report.settledGrowthMBPerCycle == 1)
    }

    @Test func detectsCPUAndMemoryRegressions() {
        let old = fixture()
        var new = old
        new.samples = old.samples.map { value in
            var result = value
            if result.phase == "tabs" { result.cpuPercent = 90 }
            if result.phase == "recovery" { result.footprintMB = 90 }
            if result.phase == "settled" { result.footprintMB += Double(result.cycle) * 3 }
            return result
        }
        let failures = new.regressions(comparedTo: old)
        #expect(failures.contains { $0.contains("mean CPU") })
        #expect(failures.contains { $0.contains("Retained footprint") })
        #expect(failures.contains { $0.contains("growth") })
        #expect(old.regressions(comparedTo: old).isEmpty)
    }

    @Test func refusesIncompleteMismatchedOrEmptyRuns() {
        let old = fixture()
        var changed = old
        changed.completed = false
        #expect(!changed.regressions(comparedTo: old).isEmpty)
        changed = old
        changed.verifiedActions["tab.1"] = 0
        #expect(!changed.regressions(comparedTo: old).isEmpty)
        changed = old
        changed.environment["reduceMotion"] = "true"
        #expect(!changed.regressions(comparedTo: old).isEmpty)
        changed = old
        changed.samples = []
        #expect(!changed.regressions(comparedTo: old).isEmpty)
        changed = old
        changed.schemaVersion = 1
        #expect(!changed.regressions(comparedTo: old).isEmpty)
    }

    @Test func reportRoundTripPreservesMeasurementsAndIncludesSummary() throws {
        let report = fixture()
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(PerformanceReport.self, from: data)
        #expect(decoded.regressions(comparedTo: report).isEmpty)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["phases"] != nil)
        #expect(json["retainedMB"] as? Double == 2)
    }

    @Test func refusesDifferentOrUnrecordedMusicWorkloads() {
        let old = fixture()
        var changed = old
        changed.environment["musicApps"] = "ru.yandex.desktop.music"
        #expect(changed.regressions(comparedTo: old) == ["Environment differs: musicApps"])
        changed.environment.removeValue(forKey: "musicApps")
        #expect(!changed.regressions(comparedTo: old).isEmpty)
        #expect(!changed.regressions(comparedTo: changed).isEmpty)
    }

    private func fixture() -> PerformanceReport {
        var report = PerformanceReport(environment: ["os": "test", "cpuCount": "8", "displays": "test",
                                                      "reduceMotion": "false", "lowPower": "false", "musicApps": ""],
                                       configuration: ["cycles": "3"])
        report.completed = true
        report.verifiedActions = ["tab.1": 3]
        report.samples = [sample(cpu: 0, phase: "baseline"), sample(cpu: 20),
                          sample(cpu: 0, memory: 52, phase: "recovery")]
        for cycle in 0..<3 {
            report.samples.append(sample(cpu: 0, memory: Double(50 + cycle), phase: "settled", cycle: cycle))
        }
        return report
    }
}
