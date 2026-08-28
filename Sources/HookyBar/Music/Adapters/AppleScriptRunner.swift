import AppKit

enum AppleScriptRunner {
    private static let lock = NSLock()

    static func command(_ source: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    static func bool(_ source: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error), error == nil else { return nil }
        return result.booleanValue
    }
}
