import Foundation

/// A timed-out callback must not publish into memory read by another thread.
/// The first completion wins; consuming/abandoning releases the stored payload.
final class CDPReplyBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var finished = false
    private var abandoned = false
    private var value: Value?

    func resolve(_ value: Value?) {
        lock.lock()
        guard !finished, !abandoned else { lock.unlock(); return }
        self.value = value
        finished = true
        lock.unlock()
        semaphore.signal()
    }

    func take(timeout: TimeInterval) -> Value? {
        let completed = semaphore.wait(timeout: .now() + timeout) == .success
        lock.lock()
        defer { lock.unlock() }
        let result = completed ? value : nil
        value = nil
        abandoned = true
        return result
    }
}
