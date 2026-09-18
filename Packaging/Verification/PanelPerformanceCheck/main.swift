import AppKit
import ApplicationServices
import Darwin
import Foundation
import CryptoKit
import HookyPerformanceSupport

struct CheckError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

struct Options {
    var app = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Hooky bar.app")
    var output: URL?
    var baseline: URL?
    var cycles = 8
    let warmup = 2
    let step = 0.8
    let settle = 3.0
    let idle = 10.0

    init() throws {
        var args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--help") {
            print("""
            HookyPanelPerformanceCheck --report /absolute/new-report.json [--cycles 8]
              [--app /absolute/Hooky\u{20}bar.app] [--baseline /absolute/previous-report.json]
            Tests the RUNNING production app. Requires Accessibility permission for
            the invoking terminal. Moves the pointer; do not use it during the run.
            Moving the pointer or holding Escape aborts. Never edits notes, copies
            clipboard contents, deletes data or presses music controls.
            No baseline: measurements only, NOT a performance pass.
            Exit: 0 complete; 1 regression; 2 interrupted/invalid/incomplete.
            """)
            exit(0)
        }
        while !args.isEmpty {
            let flag = args.removeFirst()
            guard !args.isEmpty else { throw CheckError("Missing value for \(flag)") }
            let value = args.removeFirst()
            switch flag {
            case "--report", "--baseline", "--app":
                guard value.hasPrefix("/") else { throw CheckError("Paths must be absolute") }
                let url = URL(fileURLWithPath: value)
                if flag == "--report" { output = url }
                if flag == "--baseline" { baseline = url }
                if flag == "--app" { app = url }
            case "--cycles":
                guard let count = Int(value), (3...30).contains(count) else {
                    throw CheckError("--cycles must be 3...30")
                }
                cycles = count
            default: throw CheckError("Unknown option \(flag)")
            }
        }
        guard let output else { throw CheckError("--report is required") }
        guard !FileManager.default.fileExists(atPath: output.path) else {
            throw CheckError("Refusing to overwrite an existing report")
        }
    }

    var configuration: [String: String] {
        ["scenario": "panel-v1", "cycles": String(cycles), "warmup": String(warmup),
         "stepSeconds": String(step), "settleSeconds": String(settle), "idleSeconds": String(idle),
         "sampleSeconds": "0.25"]
    }
}

// Samples only the target PID, not this runner, Codex, or total system CPU.
// Process start time is checked so a crash/restart never produces a false win.
final class Sampler {
    private let pid: pid_t
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "Hooky.performance.sampling")
    private var timer: DispatchSourceTimer?
    private var previous: UsageReading?
    private var startTime: UInt64?
    private var phase = "warmup"
    private var cycle = -1
    private var readings: [UsageSample] = []
    private var failure: String?

    init(pid: pid_t) { self.pid = pid }

    func start() {
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: 0.25, leeway: .milliseconds(10))
        source.setEventHandler { [weak self] in self?.sample() }
        timer = source
        source.resume()
    }

    func mark(_ phase: String, cycle: Int) {
        queue.sync {
            // End the preceding interval at the boundary. Keeping this reading
            // captures the FIRST animation frame too, instead of skipping 250 ms.
            sample()
            lock.lock(); defer { lock.unlock() }
            self.phase = phase
            self.cycle = cycle
        }
    }

    func check() throws {
        lock.lock(); defer { lock.unlock() }
        if let failure { throw CheckError(failure) }
    }

    func stop() -> [UsageSample] {
        timer?.cancel()
        queue.sync {}
        lock.lock(); defer { lock.unlock() }
        return readings
    }

    private func sample() {
        let usage = try? NativeProcessUsage.read(pid: pid)
        lock.lock(); defer { lock.unlock() }
        guard let usage else { failure = "Target exited or proc_pid_rusage failed"; return }
        if let startTime, startTime != usage.processStart {
            failure = "Target process restarted during the test"
            return
        }
        startTime = usage.processStart
        let now = usage.reading
        if let previous, let interval = now.interval(since: previous, phase: phase, cycle: cycle) {
            readings.append(interval)
        }
        previous = now
    }
}

final class PanelDriver {
    private let app: AXUIElement
    private let sampler: Sampler
    private let originalPointer: CGPoint
    private var expectedPointer: CGPoint?
    private var userInterrupted = false
    var actions: [String: Int] = [:]
    var skipped: Set<String> = []

    init(pid: pid_t, sampler: Sampler) {
        self.app = AXUIElementCreateApplication(pid)
        self.sampler = sampler
        self.originalPointer = CGEvent(source: nil)!.location
        AXUIElementSetMessagingTimeout(app, 1)
    }

    func restorePointer() {
        // Never fight the user after they have taken control of the pointer.
        if !userInterrupted && expectedPointer != nil { postMove(originalPointer) }
    }

    func pause(_ seconds: Double) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        repeat {
            try sampler.check()
            let location = CGEvent(source: nil)!.location
            if CGEventSource.keyState(.combinedSessionState, key: 53) ||
                (expectedPointer.map { hypot(location.x - $0.x, location.y - $0.y) > 4 } ?? false) {
                userInterrupted = true
                throw CheckError("User interrupted the run; no further clicks were sent")
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while ProcessInfo.processInfo.systemUptime < deadline
    }

    func window() throws -> AXUIElement {
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        guard let window = windows.first(where: { string($0, kAXIdentifierAttribute) == "hooky.main-panel" }) else {
            throw CheckError("Main panel AX identifier missing; install the current build first")
        }
        return window
    }

    private func frame() throws -> CGRect {
        let window = try window()
        guard let rawPosition = attribute(window, kAXPositionAttribute),
              let rawSize = attribute(window, kAXSizeAttribute),
              CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() else {
            throw CheckError("Cannot read main panel geometry")
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position),
              AXValueGetValue(rawSize as! AXValue, .cgSize, &size),
              size.width >= 300, size.width <= 600, size.height >= 200, size.height <= 600 else {
            throw CheckError("Unexpected main panel geometry; refusing pointer input")
        }
        return CGRect(origin: position, size: size)
    }

    func expand(delay: Double) throws {
        let rect = try frame()
        try move(CGPoint(x: rect.midX, y: rect.minY + 12))
        try waitFor("panel did not expand") { try self.find("hooky.tab.0") != nil }
        try move(CGPoint(x: rect.midX, y: rect.minY + 60))
        try pause(delay)
        actions["expand", default: 0] += 1
    }

    func collapse(delay: Double) throws {
        let rect = try frame()
        // Below this panel, not a click on a different app or a menu-bar item.
        try move(CGPoint(x: rect.midX, y: rect.maxY + 20))
        try waitFor("panel did not collapse") { try self.find("hooky.tab.0") == nil }
        try pause(delay)
        actions["collapse", default: 0] += 1
    }

    func press(_ identifier: String, delay: Double) throws {
        try pause(0.01)
        guard let element = try find(identifier), string(element, kAXRoleAttribute) == kAXButtonRole else {
            throw CheckError("Required navigation button missing: \(identifier)")
        }
        let allowed = identifier.hasPrefix("hooky.tab.") || identifier.hasPrefix("hooky.clipboard.filter.")
        guard allowed else { throw CheckError("Button is outside the safe navigation allowlist") }
        guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
            throw CheckError("AXPress failed: \(identifier)")
        }
        try waitFor("button did not become selected: \(identifier)") {
            guard let selected = try self.find(identifier) else { return false }
            return self.string(selected, kAXValueAttribute) == "selected"
        }
        try pause(delay)
        actions[identifier, default: 0] += 1
    }

    func hasDev() throws -> Bool { try find("hooky.tab.3") != nil }

    func scroll(delay: Double) throws {
        let nodes = try descendants()
        guard let area = nodes.first(where: { string($0, kAXRoleAttribute) == kAXScrollAreaRole }) else {
            skipped.insert("dev-scroll: no scroll area")
            return
        }
        let bars = attribute(area, kAXChildrenAttribute) as? [AXUIElement] ?? []
        guard let bar = bars.first(where: {
            string($0, kAXRoleAttribute) == kAXScrollBarRole &&
            string($0, kAXOrientationAttribute) == kAXVerticalOrientationValue
        }), let before = attribute(bar, kAXValueAttribute) as? Double else {
            skipped.insert("dev-scroll: no vertical scrollbar/content fits")
            return
        }
        let rect = try frame()
        try move(CGPoint(x: rect.midX, y: rect.maxY - 60))
        for amount: Int32 in [-220, 220] {
            guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                      wheel1: amount, wheel2: 0, wheel3: 0) else {
                throw CheckError("Cannot create scroll event")
            }
            event.location = expectedPointer!
            // Send through normal window hit-testing. Direct-to-PID scrolls can
            // arrive without a target NSWindow and be discarded by AppKit.
            event.post(tap: .cghidEventTap)
            try pause(delay)
            if amount < 0 {
                let refreshed = try descendants().first {
                    string($0, kAXRoleAttribute) == kAXScrollBarRole &&
                    string($0, kAXOrientationAttribute) == kAXVerticalOrientationValue
                }
                guard let refreshed, let after = attribute(refreshed, kAXValueAttribute) as? Double,
                      abs(after - before) > 0.001 else {
                    throw CheckError("Scroll input did not move the native scrollbar")
                }
            }
        }
        actions["dev-scroll-pair", default: 0] += 1
        try move(CGPoint(x: rect.midX, y: rect.minY + 60))
    }

    private func move(_ point: CGPoint) throws {
        try pause(0.01)
        postMove(point)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.3
        while hypot(CGEvent(source: nil)!.location.x - point.x, CGEvent(source: nil)!.location.y - point.y) > 4 {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw CheckError("Pointer input was not delivered")
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        expectedPointer = point
    }

    private func postMove(_ point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point,
                mouseButton: .left)?.post(tap: .cghidEventTap)
    }

    private func waitFor(_ message: String, condition: () throws -> Bool) throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        while !(try condition()) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw CheckError(message) }
            try pause(0.1)
        }
    }

    private func find(_ identifier: String) throws -> AXUIElement? {
        try descendants().first { string($0, kAXIdentifierAttribute) == identifier }
    }

    private func descendants() throws -> [AXUIElement] {
        var queue = [try window()]
        var result: [AXUIElement] = []
        // Bound traversal. No title/value/text fields are collected in reports.
        while !queue.isEmpty && result.count < 1500 {
            let node = queue.removeFirst()
            result.append(node)
            queue.append(contentsOf: attribute(node, kAXChildrenAttribute) as? [AXUIElement] ?? [])
        }
        return result
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func string(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }
}

// Only record supported player presence, never track metadata or playback
// commands. A player starting/stopping changes Hooky's polling workload.
func runningMusicApps() -> String {
    ["com.apple.Music", "com.spotify.client", "ru.yandex.desktop.music"].filter {
        NSRunningApplication.runningApplications(withBundleIdentifier: $0).contains { !$0.isTerminated }
    }.joined(separator: ",")
}

func run(_ options: Options) throws -> Int32 {
    guard AXIsProcessTrusted() else {
        throw CheckError("Accessibility access is unavailable. Enable it for your terminal, then rerun; nothing was clicked.")
    }
    let executable = options.app.appendingPathComponent("Contents/MacOS/HookyBar").standardizedFileURL.resolvingSymlinksInPath()
    let matches = NSRunningApplication.runningApplications(withBundleIdentifier: "com.yarxhe.HookyBar").filter {
        $0.executableURL?.standardizedFileURL.resolvingSymlinksInPath() == executable
    }
    guard matches.count == 1, let application = matches.first else {
        throw CheckError("Expected exactly one running Hooky bar at the requested path; nothing was launched")
    }
    let environment = [
        "os": ProcessInfo.processInfo.operatingSystemVersionString,
        "cpuCount": String(ProcessInfo.processInfo.processorCount),
        "displays": NSScreen.screens.map { "\($0.frame.width)x\($0.frame.height)@\($0.backingScaleFactor)" }.joined(separator: ","),
        "reduceMotion": String(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion),
        "lowPower": String(ProcessInfo.processInfo.isLowPowerModeEnabled),
        "musicApps": runningMusicApps(),
        "appVersion": Bundle(url: options.app)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
        "pid": String(application.processIdentifier),
        "executableSHA256": SHA256.hash(data: try Data(contentsOf: executable, options: .mappedIfSafe))
            .map { String(format: "%02x", $0) }.joined(),
        "recordedAt": ISO8601DateFormatter().string(from: Date())
    ]
    var report = PerformanceReport(environment: environment, configuration: options.configuration)
    let baseline = try options.baseline.map { try JSONDecoder().decode(PerformanceReport.self, from: Data(contentsOf: $0)) }
    let sampler = Sampler(pid: application.processIdentifier)
    let driver = PanelDriver(pid: application.processIdentifier, sampler: sampler)
    defer { driver.restorePointer() }
    sampler.start()
    do {
        print("Warm-up: \(options.warmup) cycles. Move the pointer or hold Escape to abort.")
        func cycle(_ index: Int) throws {
            guard runningMusicApps() == environment["musicApps"] else {
                throw CheckError("Running music apps changed during the test; rerun with a stable workload")
            }
            sampler.mark("open", cycle: index)
            try driver.expand(delay: options.step)
            sampler.mark("tabs", cycle: index)
            try driver.press("hooky.tab.2", delay: options.step)
            try driver.press("hooky.tab.1", delay: options.step)
            sampler.mark("filters", cycle: index)
            for filter in ["text", "screenshots", "pinned", "all"] {
                try driver.press("hooky.clipboard.filter.\(filter)", delay: options.step)
            }
            if try driver.hasDev() {
                sampler.mark("tabs", cycle: index)
                try driver.press("hooky.tab.3", delay: options.step)
                sampler.mark("scroll", cycle: index)
                try driver.scroll(delay: options.step)
            } else { driver.skipped.insert("Dev disabled; not enabled by test") }
            sampler.mark("tabs", cycle: index)
            try driver.press("hooky.tab.0", delay: options.step)
            sampler.mark("close", cycle: index)
            try driver.collapse(delay: options.step)
            sampler.mark("settle", cycle: index)
            try driver.pause(options.settle)
            sampler.mark("settled", cycle: index)
            try driver.pause(1.5)
        }
        for _ in 0..<options.warmup { try cycle(-1) }
        driver.actions = [:]
        sampler.mark("baseline", cycle: 0)
        try driver.pause(options.idle)
        for index in 0..<options.cycles {
            print("Cycle \(index + 1)/\(options.cycles)")
            try cycle(index)
        }
        sampler.mark("recovery", cycle: options.cycles)
        try driver.pause(options.idle)
        try sampler.check()
        guard runningMusicApps() == environment["musicApps"] else {
            throw CheckError("Running music apps changed during the test; rerun with a stable workload")
        }
        report.completed = true
    } catch { report.failure = String(describing: error) }
    report.samples = sampler.stop()
    report.verifiedActions = driver.actions
    report.skipped = driver.skipped.sorted()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: options.output!, options: .withoutOverwriting)
    for (name, phase) in report.phases.sorted(by: { $0.key < $1.key }) {
        print(String(format: "%@: CPU mean %.1f%% / p95 %.1f%% / peak %.1f%%; footprint median %.1f / peak %.1f MiB",
                     name, phase.meanCPU, phase.p95CPU, phase.peakCPU, phase.medianFootprintMB, phase.peakFootprintMB))
    }
    if let retained = report.retainedMB { print(String(format: "Retained after recovery: %+.1f MiB", retained)) }
    if let slope = report.settledGrowthMBPerCycle { print(String(format: "Settled trend: %+.2f MiB/cycle", slope)) }
    print("Report: \(options.output!.path)")
    guard report.completed else { print("INCOMPLETE: \(report.failure ?? "unknown")"); return 2 }
    if let baseline {
        let failures = report.regressions(comparedTo: baseline)
        if !failures.isEmpty { failures.forEach { print("REGRESSION: \($0)") }; return 1 }
        print("PASS: verified scenario and no regressions against the supplied baseline")
    } else { print("MEASURED: UI actions verified; no performance verdict without an approved baseline") }
    return 0
}

setbuf(stdout, nil)
do { exit(try run(Options())) }
catch { fputs("Panel performance check: \(error)\n", stderr); exit(2) }
