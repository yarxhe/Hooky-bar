import Foundation
import Testing
@testable import HookyBar

struct BoundedProcessTests {
    @Test func capturesOutputAndEnforcesTimeout() {
        let echo = BoundedProcess.run(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["hooky"],
            timeout: 1,
            outputLimit: 128
        )
        #expect(echo?.terminationStatus == 0)
        #expect(String(data: echo?.output ?? Data(), encoding: .utf8)?.contains("hooky") == true)

        let started = Date()
        let timeout = BoundedProcess.run(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"],
            timeout: 0.05
        )
        #expect(timeout == nil)
        #expect(Date().timeIntervalSince(started) < 1)
    }
}
