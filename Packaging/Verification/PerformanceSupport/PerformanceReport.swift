import Foundation

public struct UsageReading: Sendable {
    public let time: Double
    public let cpuSeconds: Double
    public let footprintBytes: UInt64

    public init(time: Double, cpuSeconds: Double, footprintBytes: UInt64) {
        self.time = time
        self.cpuSeconds = cpuSeconds
        self.footprintBytes = footprintBytes
    }

    public func interval(since previous: Self, phase: String, cycle: Int) -> UsageSample? {
        let elapsed = time - previous.time
        guard elapsed > 0, cpuSeconds >= previous.cpuSeconds else { return nil }
        return UsageSample(time: time, duration: elapsed,
                           cpuPercent: (cpuSeconds - previous.cpuSeconds) / elapsed * 100,
                           footprintMB: Double(footprintBytes) / 1_048_576, phase: phase, cycle: cycle)
    }
}

public struct UsageSample: Codable, Sendable {
    public var time: Double
    public var duration: Double
    public var cpuPercent: Double
    public var footprintMB: Double
    public var phase: String
    public var cycle: Int
}

public struct PhaseSummary: Codable, Sendable {
    public let samples: Int
    public let seconds: Double
    public let meanCPU: Double
    public let p95CPU: Double
    public let peakCPU: Double
    public let medianFootprintMB: Double
    public let peakFootprintMB: Double

    public init?(_ readings: [UsageSample]) {
        guard !readings.isEmpty else { return nil }
        samples = readings.count
        seconds = readings.reduce(0) { $0 + $1.duration }
        guard seconds > 0 else { return nil }
        meanCPU = readings.reduce(0) { $0 + $1.cpuPercent * $1.duration } / seconds
        p95CPU = Self.percentile(readings.map(\.cpuPercent), 0.95)
        peakCPU = readings.map(\.cpuPercent).max()!
        medianFootprintMB = Self.percentile(readings.map(\.footprintMB), 0.5)
        peakFootprintMB = readings.map(\.footprintMB).max()!
    }

    private static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        let sorted = values.sorted()
        return sorted[max(0, Int(ceil(Double(sorted.count) * percentile)) - 1)]
    }
}

public struct PerformanceReport: Codable, Sendable {
    // Version 1 incorrectly treated Mach ticks as nanoseconds on Apple Silicon.
    // Never compare its CPU figures with corrected reports.
    public var schemaVersion = 2
    public var completed = false
    public var failure: String?
    public var environment: [String: String]
    public var configuration: [String: String]
    public var verifiedActions: [String: Int] = [:]
    public var skipped: [String] = []
    public var samples: [UsageSample] = []

    public init(environment: [String: String], configuration: [String: String]) {
        self.environment = environment
        self.configuration = configuration
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, completed, failure, environment, configuration, verifiedActions, skipped, samples
    }

    private enum SummaryKeys: String, CodingKey {
        case phases, retainedMB, settledFootprintMB, settledGrowthMBPerCycle
    }

    public func encode(to encoder: Encoder) throws {
        var data = encoder.container(keyedBy: CodingKeys.self)
        try data.encode(schemaVersion, forKey: .schemaVersion)
        try data.encode(completed, forKey: .completed)
        try data.encodeIfPresent(failure, forKey: .failure)
        try data.encode(environment, forKey: .environment)
        try data.encode(configuration, forKey: .configuration)
        try data.encode(verifiedActions, forKey: .verifiedActions)
        try data.encode(skipped, forKey: .skipped)
        try data.encode(samples, forKey: .samples)
        var summary = encoder.container(keyedBy: SummaryKeys.self)
        try summary.encode(phases, forKey: .phases)
        try summary.encodeIfPresent(retainedMB, forKey: .retainedMB)
        try summary.encode(settledFootprintMB, forKey: .settledFootprintMB)
        try summary.encodeIfPresent(settledGrowthMBPerCycle, forKey: .settledGrowthMBPerCycle)
    }

    public var phases: [String: PhaseSummary] {
        Dictionary(grouping: samples.filter { $0.cycle >= 0 }, by: \.phase)
            .compactMapValues { PhaseSummary($0) }
    }

    public var retainedMB: Double? {
        guard let before = phases["baseline"], let after = phases["recovery"] else { return nil }
        return after.medianFootprintMB - before.medianFootprintMB
    }

    public var settledFootprintMB: [Int: Double] {
        Dictionary(grouping: samples.filter { $0.phase == "settled" && $0.cycle >= 0 }, by: \.cycle)
            .compactMapValues { PhaseSummary($0)?.medianFootprintMB }
    }

    /// Regression signal, not a claim that retained allocations are a leak.
    public var settledGrowthMBPerCycle: Double? {
        let points = settledFootprintMB
        guard points.count >= 3 else { return nil }
        let xMean = points.keys.reduce(0.0) { $0 + Double($1) } / Double(points.count)
        let yMean = points.values.reduce(0, +) / Double(points.count)
        let denominator = points.keys.reduce(0.0) { $0 + pow(Double($1) - xMean, 2) }
        return points.reduce(0.0) { $0 + (Double($1.key) - xMean) * ($1.value - yMean) } / denominator
    }

    /// Comparisons deliberately reject incomplete/different runs. A cold restart,
    /// fewer verified clicks or a different Reduce Motion setting is not a win.
    public func regressions(comparedTo baseline: Self) -> [String] {
        guard completed, baseline.completed else { return ["Cannot compare incomplete runs"] }
        guard schemaVersion == baseline.schemaVersion,
              configuration == baseline.configuration,
              verifiedActions == baseline.verifiedActions,
              skipped == baseline.skipped else { return ["Scenario or verified actions differ"] }
        for key in ["os", "cpuCount", "displays", "reduceMotion", "lowPower", "musicApps"] {
            guard environment[key] != nil, environment[key] == baseline.environment[key] else {
                return ["Environment differs: \(key)"]
            }
        }
        guard phases.keys.sorted() == baseline.phases.keys.sorted(),
              let retainedMB, let baselineRetained = baseline.retainedMB else {
            return ["Missing comparable measurements"]
        }
        var failures: [String] = []
        for (name, previous) in baseline.phases {
            let current = phases[name]!
            // A 25% relative tolerance plus 3 percentage points handles near-zero
            // idle CPU without interpreting small scheduling noise as a failure.
            if current.meanCPU > previous.meanCPU * 1.25 + 3 {
                failures.append("\(name): mean CPU exceeds baseline tolerance")
            }
            if current.p95CPU > previous.p95CPU * 1.35 + 8 {
                failures.append("\(name): p95 CPU exceeds baseline tolerance")
            }
            if current.peakFootprintMB > previous.peakFootprintMB * 1.2 + 8 {
                failures.append("\(name): peak footprint exceeds baseline tolerance")
            }
        }
        if retainedMB > max(0, baselineRetained) + 12 {
            failures.append("Retained footprint exceeds baseline by more than 12 MiB")
        }
        if let slope = settledGrowthMBPerCycle, let oldSlope = baseline.settledGrowthMBPerCycle,
           slope > max(0, oldSlope) + 1.5 {
            failures.append("Settled footprint growth exceeds baseline by more than 1.5 MiB/cycle")
        }
        return failures
    }
}
