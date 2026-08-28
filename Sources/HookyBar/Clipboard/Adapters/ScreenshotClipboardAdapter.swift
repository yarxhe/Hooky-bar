import AppKit
import UniformTypeIdentifiers

final class ScreenshotClipboardAdapter: ClipboardSourceAdapter {
    let id = "system.screenshots"
    var displayName: String { L10n.tr("clipboard.source.screenshots") }
    let capability = IntegrationCapabilityDeclaration(
        id: "clipboard.screenshots",
        permissions: [.desktopFolder]
    )

    private var items: [ClipboardItem] = []
    private var knownURLs = Set<URL>()
    private var didLoadInitialItems = false
    private var receive: ((ClipboardAdapterUpdate) -> Void)?
    private var watcher: DispatchSourceFileSystemObject?
    private var directoryFileDescriptor: Int32 = -1
    private var pendingRefresh: DispatchWorkItem?

    func start(receive: @escaping (ClipboardAdapterUpdate) -> Void) {
        guard watcher == nil else { return }
        self.receive = receive
        refresh()
        startWatcher()
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        pendingRefresh?.cancel()
        pendingRefresh = nil
        receive = nil
    }

    func copy(_ item: ClipboardItem) -> IntegrationResult {
        guard let url = item.fileURL, let image = NSImage(contentsOf: url) else {
            return .failed(.unavailable)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([image]) ? .success : .failed(.commandRejected)
    }

    func remove(_ item: ClipboardItem) -> IntegrationResult {
        items.removeAll { $0.id == item.id }
        publish()
        return .success
    }

    private func refresh() {
        let folder = screenshotFolder()
        let keys: Set<URLResourceKey> = [.creationDateKey, .contentTypeKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []

        let urls = files.filter(isScreenshot).sorted {
            creationDate(for: $0, keys: keys) > creationDate(for: $1, keys: keys)
        }
        let limited = Array(urls.prefix(40))
        let previous = knownURLs
        items = limited.map { url in
            ClipboardItem(
                id: "screenshot:\(url.path)",
                sourceID: id,
                sourceName: displayName,
                sourceBundleIdentifier: nil,
                kind: .screenshot,
                text: nil,
                fileURL: url,
                createdAt: creationDate(for: url, keys: keys)
            )
        }
        knownURLs = Set(limited)
        let inserted = didLoadInitialItems
            ? items.first(where: { item in item.fileURL.map { !previous.contains($0) } ?? false })
            : nil
        didLoadInitialItems = true
        publish(inserted: inserted)
    }

    private func publish(inserted: ClipboardItem? = nil) {
        receive?(ClipboardAdapterUpdate(sourceID: id, items: items, insertedItem: inserted))
    }

    private func isScreenshot(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        return ["png", "jpg", "jpeg", "heic"].contains(url.pathExtension.lowercased())
            && (name.hasPrefix("снимок экрана") || name.hasPrefix("screenshot"))
    }

    private func creationDate(for url: URL, keys: Set<URLResourceKey>) -> Date {
        (try? url.resourceValues(forKeys: keys))?.creationDate ?? .distantPast
    }

    private func screenshotFolder() -> URL {
        let configured = UserDefaults.standard
            .persistentDomain(forName: "com.apple.screencapture")?["location"] as? String
        return configured.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
            ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
    }

    private func startWatcher() {
        let descriptor = open(screenshotFolder().path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        directoryFileDescriptor = descriptor
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self, pendingRefresh == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                self?.pendingRefresh = nil
                self?.refresh()
            }
            pendingRefresh = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: work)
        }
        source.setCancelHandler { [weak self] in
            guard let self, directoryFileDescriptor >= 0 else { return }
            close(directoryFileDescriptor)
            directoryFileDescriptor = -1
        }
        watcher = source
        source.resume()
    }
}
