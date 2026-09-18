import Foundation
import Network
import Testing
@testable import HookyBar

@Suite(.serialized)
struct YandexCDPLifecycleTests {
    @Test func lateRepliesAndDuplicateCompletionsDoNotRetainPayload() {
        final class Payload {}
        let reply = CDPReplyBox<Payload>()
        #expect(reply.take(timeout: 0.001) == nil)
        weak var reference: Payload?
        autoreleasepool {
            let payload = Payload()
            reference = payload
            reply.resolve(payload)
        }
        #expect(reference == nil)
        let firstWins = CDPReplyBox<Int>()
        firstWins.resolve(1)
        firstWins.resolve(2)
        #expect(firstWins.take(timeout: 0.01) == 1)
    }

    @Test func absentOwnerBacksOffButExplicitCommandChecksImmediately() {
        var now = Date()
        var probes = 0
        let bridge = YandexCDPBridge(port: 54321, expectedBundleIdentifier: "fixture",
            clock: { now }, ownerProbe: { probes += 1; return false })
        for _ in 0..<100 { #expect(!bridge.isAvailable()) }
        #expect(probes == 1)
        now.addTimeInterval(3.1)
        #expect(!bridge.isAvailable())
        #expect(probes == 2)
        #expect(!bridge.startPlaybackIfNeeded()) // No endpoint is contacted.
        #expect(probes == 3)
    }

    @Test func credentialsAndFragmentsAreNotAccepted() throws {
        for suffix in ["user@127.0.0.1:54321/devtools/page/a", "127.0.0.1:54321/devtools/page/a#fragment"] {
            #expect(!YandexCDPBridge.isTrustedWebSocketURL(try #require(URL(string: "ws://" + suffix)), port: 54321))
        }
    }

    @Test func realTransportReleasesConnectionsAndSkipsEvents() async throws {
        let server = try CDPFixture(mode: "events")
        defer { server.stop() }
        let tracker = ConnectionTracker()
        let bridge = YandexCDPBridge(port: server.port, expectedBundleIdentifier: "fixture",
            ownerProbe: { true }, connectionFactory: tracker.makeConnection)
        for _ in 0..<80 {
            let result = autoreleasepool { bridge.playbackState() }
            #expect(result == false)
        }
        try await expectDrained(server, tracker)
        let stats = try server.stats()
        #expect(stats["requests"] == 80)
        #expect(stats["discoveries"] == 1)
        #expect(stats["origins"] == 0)
    }

    @Test func timeoutDisconnectAndOversizedMessageCloseAllConnections() async throws {
        for mode in ["stall", "disconnect", "oversized"] {
            let server = try CDPFixture(mode: mode)
            defer { server.stop() }
            let tracker = ConnectionTracker()
            let bridge = YandexCDPBridge(port: server.port, expectedBundleIdentifier: "fixture",
                ownerProbe: { true }, connectionFactory: tracker.makeConnection, replyTimeout: 0.15)
            for _ in 0..<8 {
                let result = autoreleasepool { bridge.playbackState() }
                #expect(result == nil, "mode=\(mode)")
            }
            try await expectDrained(server, tracker)
            let opened = try #require(server.stats()["opened"])
            #expect((8...16).contains(opened), "mode=\(mode) opened=\(opened)")
        }
    }

    @Test func nonIdempotentPlaybackCommandIsNeverRetriedAfterLostReply() async throws {
        let server = try CDPFixture(mode: "stall")
        defer { server.stop() }
        let tracker = ConnectionTracker()
        let bridge = YandexCDPBridge(
            port: server.port,
            expectedBundleIdentifier: "fixture",
            ownerProbe: { true },
            connectionFactory: tracker.makeConnection,
            replyTimeout: 0.15
        )

        #expect(!bridge.playPause())
        try await expectDrained(server, tracker)
        let stats = try server.stats()
        #expect(stats["opened"] == 1)
        #expect(stats["requests"] == 1)
    }

    @Test func failedDiscoveryBacksOffWithoutKeepingTheConnection() async throws {
        let server = try CDPFixture(mode: "missing")
        defer { server.stop() }
        var now = Date()
        let tracker = ConnectionTracker()
        let bridge = YandexCDPBridge(port: server.port, expectedBundleIdentifier: "fixture",
            clock: { now }, ownerProbe: { true }, connectionFactory: tracker.makeConnection)
        for _ in 0..<50 { #expect(!bridge.isAvailable()) }
        #expect(try server.stats()["discoveries"] == 1)
        now.addTimeInterval(3.1)
        #expect(!bridge.isAvailable())
        #expect(try server.stats()["discoveries"] == 2)
        #expect(!bridge.startPlaybackIfNeeded())
        #expect(try server.stats()["discoveries"] == 3)
        try await expectDrained(server, tracker)
    }

    // Opt-in separate-process soak: do not mix its footprint with parallel UI tests.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["HOOKY_CDP_SOAK"] == "1"))
    func transportMemorySoak() async throws {
        let server = try CDPFixture(mode: "events")
        defer { server.stop() }
        let tracker = ConnectionTracker()
        let bridge = YandexCDPBridge(port: server.port, expectedBundleIdentifier: "fixture",
            ownerProbe: { true }, connectionFactory: tracker.makeConnection)
        var footprints: [Double] = []
        for batch in 0..<7 {
            for _ in 0..<500 {
                let result = autoreleasepool { bridge.playbackState() }
                #expect(result == false)
            }
            try await expectDrained(server, tracker)
            let footprint = try #require(HookyDiagnostics.footprintMegabytes)
            footprints.append(footprint)
            print("CDP_SOAK requests=\((batch + 1) * 500) footprint_mib=\(footprint) live_connections=\(tracker.liveCount) stats=\(try server.stats())")
        }
        // Allocator/transport warm-up is not a leak. Compare the warmed plateau.
        let retained = try #require(footprints.last) - footprints[1]
        #expect(retained < 8, "Warm retained footprint grew by \(retained) MiB")
        for mode in ["disconnect", "missing"] {
            let failures = try CDPFixture(mode: mode)
            defer { failures.stop() }
            var now = Date()
            let failedBridge = YandexCDPBridge(port: failures.port, expectedBundleIdentifier: "fixture",
                clock: { now }, ownerProbe: { true }, connectionFactory: tracker.makeConnection, replyTimeout: 0.15)
            for _ in 0..<500 {
                now.addTimeInterval(3.1)
                let result = autoreleasepool { failedBridge.playbackState() }
                #expect(result == nil)
            }
            try await expectDrained(failures, tracker)
            let footprint = try #require(HookyDiagnostics.footprintMegabytes)
            print("CDP_SOAK failures=500 mode=\(mode) footprint_mib=\(footprint) live_connections=\(tracker.liveCount) stats=\(try failures.stats())")
            #expect(footprint - footprints[1] < 8)
        }
    }

    private func expectDrained(_ server: CDPFixture, _ tracker: ConnectionTracker) async throws {
        for _ in 0..<60 {
            if tracker.liveCount == 0, try server.stats()["active"] == 0 { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        let remaining = tracker.liveCount
        print("CDP_DRAIN remaining_connections=\(remaining) stats=\(try server.stats())")
        #expect(remaining == 0)
        #expect(try server.stats()["active"] == 0)
    }
}

private final class ConnectionTracker: @unchecked Sendable {
    private final class WeakConnection { weak var value: NWConnection?; init(_ value: NWConnection) { self.value = value } }
    private let lock = NSLock()
    private var connections: [WeakConnection] = []
    var liveCount: Int {
        lock.lock(); defer { lock.unlock() }
        connections.removeAll { $0.value == nil }
        return connections.count
    }
    func makeConnection(_ endpoint: NWEndpoint, _ parameters: NWParameters) -> NWConnection {
        let connection = NWConnection(to: endpoint, using: parameters)
        lock.lock()
        connections.removeAll { $0.value == nil }
        connections.append(WeakConnection(connection))
        lock.unlock()
        return connection
    }
}

private final class CDPFixture {
    let process = Process()
    let port: UInt16
    init(mode: String) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [root.appendingPathComponent("Packaging/Verification/CDPTestServer.py").path, mode]
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.availableData
        guard let text = String(data: data, encoding: .utf8),
              let port = UInt16(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            if process.isRunning { process.terminate() }
            throw NSError(domain: "CDPFixture", code: 1)
        }
        self.port = port
    }
    func stats() throws -> [String: Int] {
        try autoreleasepool {
            let data = try Data(contentsOf: URL(string: "http://127.0.0.1:\(port)/stats")!)
            return try JSONDecoder().decode([String: Int].self, from: data)
        }
    }
    func stop() { if process.isRunning { process.terminate(); process.waitUntilExit() } }
    deinit { stop() }
}
