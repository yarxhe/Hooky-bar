import Testing
@testable import HookyBar

struct ProcessCPUReadingTests {
    @Test func computesIntervalUsageIncludingMultipleCores() {
        let first = ProcessCPUReading(uptime: 100, cpuSeconds: 10)
        #expect(ProcessCPUReading(uptime: 110, cpuSeconds: 10).percent(since: first) == 0)
        #expect(ProcessCPUReading(uptime: 110, cpuSeconds: 14.5).percent(since: first) == 45)
        #expect(ProcessCPUReading(uptime: 110, cpuSeconds: 25).percent(since: first) == 150)
        #expect(first.percent(since: first) == nil)
        #expect(ProcessCPUReading(uptime: 101, cpuSeconds: 9).percent(since: first) == nil)
    }
}
