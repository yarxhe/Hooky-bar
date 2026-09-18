import Foundation

/// Coalesce repeated panel appearances while Git/GitHub are still loading.
/// Explicit refresh bypasses the short cache, but never duplicates an active
/// request for the same workspace. Changing projects starts a fresh request.
struct DeveloperRefreshGate {
    private var path: String?
    private var startedAt: TimeInterval = -.infinity
    private var activeToken: UUID?

    mutating func begin(path: String, force: Bool, now: TimeInterval) -> UUID? {
        if self.path == path {
            if activeToken != nil { return nil }
            if !force, now - startedAt < 60 { return nil }
        }
        let token = UUID()
        self.path = path
        startedAt = now
        activeToken = token
        return token
    }

    mutating func finish(_ token: UUID) {
        guard activeToken == token else { return }
        activeToken = nil
    }
}
