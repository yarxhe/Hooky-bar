import AppKit
import Combine

/// Агрегирует встроенные и будущие SDK-источники в один список для интерфейса.
final class ClipboardStore: ObservableObject {
    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var pinnedIDs: Set<String> = []

    var onNewScreenshot: ((URL) -> Void)?

    private var adapters: [ClipboardSourceAdapter]
    private var itemsBySource: [String: [ClipboardItem]] = [:]
    private var hiddenIDs: Set<String> = []
    private var isMonitoring = false
    private let pinnedDefaultsKey = "HookyBar.clipboard.pinnedIDs"

    init(adapters: [ClipboardSourceAdapter] = [
        SystemTextClipboardAdapter(),
        ScreenshotClipboardAdapter()
    ]) {
        self.adapters = adapters
        self.pinnedIDs = Set(UserDefaults.standard.stringArray(forKey: pinnedDefaultsKey) ?? [])
    }

    var textCount: Int { items.lazy.filter { $0.kind == .text }.count }
    var screenshotCount: Int { items.lazy.filter { $0.kind == .screenshot }.count }
    var sourceCapabilities: [IntegrationCapabilityDeclaration] {
        adapters.map(\.capability).sorted { $0.id < $1.id }
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        for adapter in adapters {
            start(adapter)
        }
    }

    func stopMonitoring() {
        adapters.forEach { $0.stop() }
        isMonitoring = false
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
        hiddenIDs.insert(item.id)
        pinnedIDs.remove(item.id)
        persistPinnedIDs()
        _ = adapters.first(where: { $0.id == item.sourceID })?.remove(item)
        rebuildItems()
    }

    private func accept(_ update: ClipboardAdapterUpdate) {
        itemsBySource[update.sourceID] = update.items
        rebuildItems()
        if update.insertedItem?.kind == .screenshot, let url = update.insertedItem?.fileURL {
            onNewScreenshot?(url)
        }
    }

    private func start(_ adapter: ClipboardSourceAdapter) {
        adapter.start { [weak self] update in
            DispatchQueue.main.async { self?.accept(update) }
        }
    }

    private func rebuildItems() {
        items = itemsBySource.values
            .flatMap { $0 }
            .filter { !hiddenIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func persistPinnedIDs() {
        UserDefaults.standard.set(Array(pinnedIDs), forKey: pinnedDefaultsKey)
    }
}
