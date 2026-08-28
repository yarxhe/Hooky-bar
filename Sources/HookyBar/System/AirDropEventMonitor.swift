import AppKit
import Darwin

final class AirDropEventAdapter: SystemEventAdapter {
    let kind: HookySystemEvent.Kind = .airDrop
    let capability = IntegrationCapabilityDeclaration(
        id: "system.airdrop",
        permissions: [.downloadsFolder]
    )

    private var receive: ((HookySystemEvent) -> Void)?
    private var watcher: DispatchSourceFileSystemObject?
    private var directoryFileDescriptor: Int32 = -1
    private var knownFiles = Set<URL>()
    private var pendingRefresh: DispatchWorkItem?

    func start(receive: @escaping (HookySystemEvent) -> Void) {
        self.receive = receive
        guard watcher == nil,
              let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first else { return }
        knownFiles = currentFiles(in: downloads)
        directoryFileDescriptor = open(downloads.path, O_EVTONLY)
        guard directoryFileDescriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFileDescriptor,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scheduleRefresh(directory: downloads) }
        source.setCancelHandler { [weak self] in
            guard let self, self.directoryFileDescriptor >= 0 else { return }
            close(self.directoryFileDescriptor)
            self.directoryFileDescriptor = -1
        }
        watcher = source
        source.resume()
    }

    func stop() {
        pendingRefresh?.cancel()
        pendingRefresh = nil
        watcher?.cancel()
        watcher = nil
        knownFiles.removeAll()
        receive = nil
    }

    private func scheduleRefresh(directory: URL) {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pendingRefresh = nil
            self?.refresh(directory: directory)
        }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    private func refresh(directory: URL) {
        let current = currentFiles(in: directory)
        let added = current.subtracting(knownFiles)
        knownFiles = current
        for url in added where looksLikeAirDrop(url) {
            receive?(HookySystemEvent(
                kind: .airDrop,
                title: url.lastPathComponent,
                subtitle: L10n.tr("event.airdrop.received"),
                symbol: "square.and.arrow.down.fill",
                tint: .systemBlue,
                deduplicationKey: "airdrop-\(url.path)"
            ))
        }
    }

    private func currentFiles(in directory: URL) -> Set<URL> {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []
        return Set(urls.filter { (try? $0.resourceValues(forKeys: keys).isRegularFile) == true })
    }

    private func looksLikeAirDrop(_ url: URL) -> Bool {
        let attribute = "com.apple.quarantine"
        let size = getxattr(url.path, attribute, nil, 0, 0, 0)
        guard size > 0 else { return false }
        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { bytes in
            getxattr(url.path, attribute, bytes.baseAddress, size, 0, 0)
        }
        guard result > 0, let text = String(data: data, encoding: .utf8)?.lowercased() else { return false }
        return text.contains("airdrop") || text.contains("sharingd")
    }
}
