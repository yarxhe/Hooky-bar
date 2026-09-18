import Testing
@testable import HookyBar

struct DeveloperRefreshGateTests {
    @Test func repeatedAppearancesDoNotQueueWork() throws {
        var gate = DeveloperRefreshGate()
        let started = gate.begin(path: "/project", force: false, now: 100)
        let first = try #require(started)
        #expect(gate.begin(path: "/project", force: false, now: 101) == nil)
        #expect(gate.begin(path: "/project", force: true, now: 102) == nil)
        gate.finish(first)
        #expect(gate.begin(path: "/project", force: false, now: 159) == nil)
        #expect(gate.begin(path: "/project", force: false, now: 160) != nil)
    }

    @Test func manualRefreshAndNewProjectsBypassCacheWithoutStaleCompletion() throws {
        var gate = DeveloperRefreshGate()
        let oldStarted = gate.begin(path: "/first", force: false, now: 100)
        let old = try #require(oldStarted)
        let newStarted = gate.begin(path: "/second", force: false, now: 101)
        let new = try #require(newStarted)
        gate.finish(old)
        #expect(gate.begin(path: "/second", force: false, now: 120) == nil)
        gate.finish(new)
        #expect(gate.begin(path: "/second", force: true, now: 102) != nil)
    }
}
