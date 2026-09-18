import AppKit
import Combine

/// Агрегирует встроенные и будущие SDK-источники в один список для интерфейса.
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var pinnedIDs: Set<String> = []

    var onNewScreenshot: ((URL) -> Void)?

    private var adapters: [ClipboardSourceAdapter]
    private var itemsBySource: [String: [ClipboardItem]] = [:]
    // Tombstones only bridge the gap until a source confirms that a removed
    // item disappeared. Keeping every removed UUID forever grows memory and
    // prevents a later item with the same stable ID (for example a screenshot
    // recreated at the same path) from appearing again.
    private var hiddenIDsBySource: [String: Set<String>] = [:]
    private var isMonitoring = false
    private var monitoringGeneration = 0
    private var cleanupTimer: Timer?
    private let retentionPolicy: ClipboardRetentionPolicy
    private let pinnedDefaultsKey = "HookyBar.clipboard.pinnedIDs"

    init(
        adapters: [ClipboardSourceAdapter] = [
            SystemTextClipboardAdapter(),
            ScreenshotClipboardAdapter()
        ],
        retentionPolicy: ClipboardRetentionPolicy = .standard
    ) {
        self.adapters = adapters
        self.retentionPolicy = retentionPolicy
        self.pinnedIDs = Set(UserDefaults.standard.stringArray(forKey: pinnedDefaultsKey) ?? [])
    }

    var textCount: Int { items.lazy.filter { $0.kind == .text }.count }
    var screenshotCount: Int { items.lazy.filter { $0.kind == .screenshot }.count }
    var hasClearableItems: Bool { items.contains { !pinnedIDs.contains($0.id) } }
    var sourceCapabilities: [IntegrationCapabilityDeclaration] {
        adapters.map(\.capability).sorted { $0.id < $1.id }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        monitoringGeneration &+= 1
        for adapter in adapters {
            start(adapter)
        }
        cleanupTimer?.invalidate()
        cleanupTimer = Timer.scheduledTimer(
            withTimeInterval: retentionPolicy.cleanupInterval,
            repeats: true
        ) { [weak self] _ in
            self?.pruneHistory(referenceDate: Date())
        }
    }

    func stopMonitoring() {
        monitoringGeneration &+= 1
        isMonitoring = false
        adapters.forEach { $0.stop() }
        cleanupTimer?.invalidate()
        cleanupTimer = nil
    }

    /// Позволяет SDK зарегистрировать новый источник до запуска или прямо во время работы.
    func register(_ adapter: ClipboardSourceAdapter) {
        guard !adapters.contains(where: { $0.id == adapter.id }) else { return }
        adapters.append(adapter)
        if isMonitoring { start(adapter) }
    }

    @discardableResult
    func copy(_ item: ClipboardItem) -> Bool {
        adapters.first(where: { $0.id == item.sourceID })?.copy(item).succeeded ?? false
    }

    @discardableResult
    func open(_ item: ClipboardItem) -> Bool {
        adapters.first(where: { $0.id == item.sourceID })?.open(item).succeeded ?? false
    }

    @discardableResult
    func copyScreenshot(at url: URL) -> Bool {
        if let item = items.first(where: { $0.fileURL == url }) {
            return copy(item)
        }
        guard let image = NSImage(contentsOf: url) else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([image])
    }

    func togglePinned(_ item: ClipboardItem) {
        if pinnedIDs.contains(item.id) {
            pinnedIDs.remove(item.id)
        } else {
            pinnedIDs.insert(item.id)
        }
        persistPinnedIDs()
    }

    func remove(_ item: ClipboardItem) {
        pinnedIDs.remove(item.id)
        persistPinnedIDs()
        removeItems([item])
    }

    /// Очищает только историю Hooky bar. Текущий системный clipboard,
    /// закреплённые элементы и файлы скриншотов остаются нетронутыми.
    @discardableResult
    func clearUnpinnedHistory() -> Int {
        let removable = items.filter { !pinnedIDs.contains($0.id) }
        removeItems(removable)
        return removable.count
    }

    private func accept(_ update: ClipboardAdapterUpdate) {
        if var hidden = hiddenIDsBySource[update.sourceID] {
            let reportedIDs = Set(update.items.map(\.id))
            hidden.formIntersection(reportedIDs)
            if hidden.isEmpty {
                hiddenIDsBySource.removeValue(forKey: update.sourceID)
            } else {
                hiddenIDsBySource[update.sourceID] = hidden
            }
        }
        itemsBySource[update.sourceID] = update.items
        pruneHistory(referenceDate: Date())
        rebuildItems()
        if update.insertedItem?.kind == .screenshot, let url = update.insertedItem?.fileURL {
            onNewScreenshot?(url)
        }
    }

    private func start(_ adapter: ClipboardSourceAdapter) {
        let generation = monitoringGeneration
        adapter.start { [weak self] update in
            DispatchQueue.main.async {
                guard let self,
                      self.isMonitoring,
                      self.monitoringGeneration == generation else { return }
                self.accept(update)
            }
        }
    }

    private func rebuildItems() {
        let hiddenIDs = allHiddenIDs
        items = itemsBySource.values
            .flatMap { $0 }
            .filter { !hiddenIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func pruneHistory(referenceDate: Date) {
        let hiddenIDs = allHiddenIDs
        let visibleItems = itemsBySource.values
            .flatMap { $0 }
            .filter { !hiddenIDs.contains($0.id) }
        removeItems(retentionPolicy.itemsToRemove(
            from: visibleItems,
            pinnedIDs: pinnedIDs,
            referenceDate: referenceDate
        ))
    }

    private var allHiddenIDs: Set<String> {
        hiddenIDsBySource.values.reduce(into: Set<String>()) {
            $0.formUnion($1)
        }
    }

    private func removeItems<S: Sequence>(_ removedItems: S) where S.Element == ClipboardItem {
        let removed = Array(removedItems)
        guard !removed.isEmpty else { return }

        let removedIDs = Set(removed.map(\.id))
        for (sourceID, sourceItems) in Dictionary(grouping: removed, by: \.sourceID) {
            hiddenIDsBySource[sourceID, default: []].formUnion(sourceItems.map(\.id))
            itemsBySource[sourceID]?.removeAll { removedIDs.contains($0.id) }
            _ = adapters.first(where: { $0.id == sourceID })?.remove(sourceItems)
        }
        rebuildItems()
    }

    private func persistPinnedIDs() {
        UserDefaults.standard.set(Array(pinnedIDs), forKey: pinnedDefaultsKey)
    }
}
