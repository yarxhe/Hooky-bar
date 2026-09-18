import Foundation
import Testing
@testable import HookyBar

struct ClipboardPresentationTests {
    private func item(_ text: String) -> ClipboardItem {
        ClipboardItem(id: "preview", sourceID: "test", sourceName: "Test",
            sourceBundleIdentifier: nil, kind: .text, text: text, fileURL: nil, createdAt: Date())
    }

    @Test func linkLabelContainsOnlyHost() {
        #expect(item(" https://example.com/path?q=value \n").linkHost == "example.com")
        #expect(item("file:///tmp/example.txt").linkHost == nil)
        #expect(item("ordinary text").linkHost == nil)
    }

    @Test func previewDoesNotAlterOriginalText() {
        let text = "const value = {\n  title: 'Hello'\n};"
        let entry = item(text)
        #expect(entry.isProbablyCode)
        #expect(entry.text == text)
    }

    @Test func screenshotOpenRejectsRemoteAndMissingFiles() {
        let adapter = ScreenshotClipboardAdapter()
        for url in [URL(string: "https://example.com/image.png")!,
                    URL(fileURLWithPath: "/nonexistent-hooky-screenshot.png")] {
            let entry = ClipboardItem(id: "invalid", sourceID: adapter.id, sourceName: "Test",
                sourceBundleIdentifier: nil, kind: .screenshot, text: nil, fileURL: url, createdAt: Date())
            #expect(!adapter.open(entry).succeeded)
        }
    }

    @Test @MainActor func removedItemCanReturnAfterItsAdapterConfirmsRemoval() async {
        let adapter = ReappearingClipboardAdapter()
        let store = ClipboardStore(
            adapters: [adapter],
            retentionPolicy: ClipboardRetentionPolicy(
                maximumUnpinnedItems: 10,
                maximumAge: 60,
                cleanupInterval: 60
            )
        )
        store.startMonitoring()
        defer { store.stopMonitoring() }

        let first = adapter.makeItem(text: "first")
        adapter.publish([first])
        await Task.yield()
        #expect(store.items == [first])

        store.remove(first)
        await Task.yield()
        #expect(store.items.isEmpty)

        let replacement = adapter.makeItem(text: "replacement")
        adapter.publish([replacement])
        await Task.yield()
        #expect(store.items == [replacement])
    }

    @Test @MainActor func stoppedClipboardStoreRejectsQueuedAdapterUpdates() async {
        let adapter = ReappearingClipboardAdapter()
        let store = ClipboardStore(adapters: [adapter])
        store.startMonitoring()
        let lateUpdate = adapter.queuedUpdate(adapter.makeItem(text: "late"))

        store.stopMonitoring()
        lateUpdate()
        await Task.yield()

        #expect(store.items.isEmpty)
    }
}

private final class ReappearingClipboardAdapter: ClipboardSourceAdapter {
    let id = "test.reappearing"
    let displayName = "Test"
    let capability = IntegrationCapabilityDeclaration(id: "clipboard.test")
    private var receive: ((ClipboardAdapterUpdate) -> Void)?
    private var items: [ClipboardItem] = []

    func start(receive: @escaping (ClipboardAdapterUpdate) -> Void) {
        self.receive = receive
    }

    func stop() { receive = nil }
    func copy(_ item: ClipboardItem) -> IntegrationResult { .success }

    func remove(_ item: ClipboardItem) -> IntegrationResult {
        items.removeAll { $0.id == item.id }
        publish(items)
        return .success
    }

    func makeItem(text: String) -> ClipboardItem {
        ClipboardItem(
            id: "stable-id",
            sourceID: id,
            sourceName: displayName,
            sourceBundleIdentifier: nil,
            kind: .text,
            text: text,
            fileURL: nil,
            createdAt: Date()
        )
    }

    func publish(_ items: [ClipboardItem]) {
        self.items = items
        receive?(ClipboardAdapterUpdate(sourceID: id, items: items, insertedItem: items.first))
    }

    func queuedUpdate(_ item: ClipboardItem) -> () -> Void {
        let receive = self.receive
        return {
            receive?(ClipboardAdapterUpdate(sourceID: self.id, items: [item], insertedItem: item))
        }
    }
}
