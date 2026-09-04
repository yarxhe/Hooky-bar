import Foundation

struct ClipboardRetentionPolicy {
    let maximumUnpinnedItems: Int
    let maximumAge: TimeInterval
    let cleanupInterval: TimeInterval

    static let standard = ClipboardRetentionPolicy(
        maximumUnpinnedItems: 48,
        maximumAge: 24 * 60 * 60,
        cleanupInterval: 60 * 60
    )

    func itemsToRemove(
        from items: [ClipboardItem],
        pinnedIDs: Set<String>,
        referenceDate: Date
    ) -> [ClipboardItem] {
        let cutoff = referenceDate.addingTimeInterval(-maximumAge)
        let unpinned = items
            .filter { !pinnedIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
        let expired = unpinned.filter { $0.createdAt < cutoff }
        let active = unpinned.filter { $0.createdAt >= cutoff }
        return expired + Array(active.dropFirst(maximumUnpinnedItems))
    }
}
