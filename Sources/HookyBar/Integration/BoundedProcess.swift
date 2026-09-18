import Darwin
import Foundation

/// Runs a small trusted system executable without a shell. Output, lifetime and
/// cleanup are bounded so a broken helper cannot retain an adapter indefinitely.
enum BoundedProcess {
    struct Result {
        let output: Data
        let terminationStatus: Int32
    }

    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private let limit: Int

        init(limit: Int) { self.limit = limit }

        func append(_ incoming: Data) {
            guard !incoming.isEmpty else { return }
            lock.lock()
            defer { lock.unlock() }
            let remaining = max(0, limit - data.count)
            if remaining > 0 { data.append(incoming.prefix(remaining)) }
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    static func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int = 2 * 1_024 * 1_024
    ) -> Result? {
        let process = Process()
        let pipe = Pipe()
        let output = OutputBuffer(limit: outputLimit)
        let terminated = DispatchSemaphore(value: 0)
        let reachedEOF = DispatchSemaphore(value: 0)

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                reachedEOF.signal()
            } else {
                output.append(chunk)
            }
        }
        process.terminationHandler = { _ in terminated.signal() }

        do { try process.run() } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }
        guard terminated.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            if terminated.wait(timeout: .now() + 0.25) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = terminated.wait(timeout: .now() + 0.25)
            }
            pipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        // Give the readability handler one short turn to collect the final
        // chunk. Never perform a blocking read: descendants may inherit stdout.
        _ = reachedEOF.wait(timeout: .now() + 0.20)
        pipe.fileHandleForReading.readabilityHandler = nil
        return Result(output: output.snapshot(), terminationStatus: process.terminationStatus)
    }
}
