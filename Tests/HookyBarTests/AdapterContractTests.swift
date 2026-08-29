import AppKit
import MediaRemoteAdapter
import Testing
@testable import HookyBar

@Suite("Adapter contracts")
struct AdapterContractTests {
    @Test func integrationResultKeepsTypedFailure() {
        #expect(IntegrationResult.success.succeeded)
        let result = IntegrationResult.failed(.permissionDenied(.automation))
        #expect(!result.succeeded)
        #expect(result.failure == .permissionDenied(.automation))
    }

    @Test func notesRegistryCanReplaceBuiltInAdapter() {
        let registry = NotesAdapterRegistry.builtIn()
        let replacement = NotesAdapterDouble(app: .obsidian)
        registry.register(replacement)

        #expect(registry.adapter(for: .obsidian)?.capability.id == replacement.capability.id)
        #expect(Set(registry.registeredApps) == Set(NotesApp.allCases))
        #expect(registry.integrationCapabilities.map(\.id).contains(replacement.capability.id))
    }

    @Test func builtInRegistriesExposeCapabilities() {
        #expect(MusicAdapterRegistry().integrationCapabilities.count == MusicSource.allCases.count)
        #expect(ClipboardStore().sourceCapabilities.count == 2)
        #expect(!ToolsStore().utilityCapabilities.isEmpty)
    }

    /// По умолчанию тест ничего не меняет. В release-smoke он записывает обратно
    /// текущее значение, проверяя именно CoreAudio-маршрут активного устройства.
    @Test func activeOutputVolumeRoundTrip() {
        guard ProcessInfo.processInfo.environment["HOOKYBAR_HARDWARE_TEST"] == "1" else { return }
        let original = SystemVolume.current()
        #expect(SystemVolume.set(original))
        #expect(abs(SystemVolume.current() - original) < 0.02)
    }

    @Test func musicTrackAndLateArtworkHaveIndependentRevisions() {
        let store = MusicStore()
        let first = MusicAdapterSnapshot(
            title: "Track",
            artist: "Artist",
            duration: 120,
            elapsed: 0,
            isPlaying: true,
            artwork: nil,
            rating: nil
        )
        store.applyAdapterSnapshot(first, marksSystemOwnership: false)
        let trackRevision = store.trackPresentationRevision
        let initialArtworkRevision = store.artworkPresentationRevision

        let artwork = NSImage(size: NSSize(width: 32, height: 32))
        artwork.lockFocus()
        NSColor.systemPurple.setFill()
        NSRect(x: 0, y: 0, width: 32, height: 32).fill()
        artwork.unlockFocus()

        let withArtwork = MusicAdapterSnapshot(
            title: first.title,
            artist: first.artist,
            duration: first.duration,
            elapsed: 1,
            isPlaying: true,
            artwork: artwork,
            rating: nil
        )
        store.applyAdapterSnapshot(withArtwork, marksSystemOwnership: false)

        #expect(store.trackPresentationRevision == trackRevision)
        #expect(store.artworkPresentationRevision == initialArtworkRevision + 1)
    }

    @Test func systemEventAdapterIsStartedThroughStoreRegistry() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "feature.vpn")
        defer {
            if let previous { defaults.set(previous, forKey: "feature.vpn") }
            else { defaults.removeObject(forKey: "feature.vpn") }
        }

        let store = SystemFeatureStore()
        let adapter = SystemEventAdapterDouble(kind: .vpn)
        store.register(adapter)
        store.setVPNEnabled(true)

        #expect(adapter.startCount == 1)
        #expect(store.systemCapabilities.contains(adapter.capability))
        store.stop()
        #expect(adapter.stopCount == 1)
    }

    @Test func systemEventLayoutExtendsBelowCompactChrome() {
        let ui = InterfaceModel()
        ui.notchWidth = 204
        ui.notchHeight = 32
        ui.hideLeftMusicWing = false
        let eventID = UUID()

        let layout = ui.surfaceLayout(hasCompactContent: false, systemEventID: eventID)

        #expect(layout.mode == .systemEvent(eventID))
        #expect(layout.width == 316)
        #expect(layout.height == 84)
        #expect(layout.bottomLeadingRadius == 18)
        #expect(layout.bottomTrailingRadius == 18)
    }

    @Test func yandexCDPOnlyAcceptsItsLoopbackPageSocket() throws {
        let port: UInt16 = 54_321
        let valid = try #require(URL(string: "ws://127.0.0.1:\(port)/devtools/page/player"))
        let wrongHost = try #require(URL(string: "ws://example.com:\(port)/devtools/page/player"))
        let wrongPort = try #require(URL(string: "ws://127.0.0.1:9222/devtools/page/player"))
        let wrongPath = try #require(URL(string: "ws://127.0.0.1:\(port)/devtools/browser/session"))
        let encryptedRemote = try #require(URL(string: "wss://127.0.0.1:\(port)/devtools/page/player"))

        #expect(YandexCDPBridge.isTrustedWebSocketURL(valid, port: port))
        #expect(!YandexCDPBridge.isTrustedWebSocketURL(wrongHost, port: port))
        #expect(!YandexCDPBridge.isTrustedWebSocketURL(wrongPort, port: port))
        #expect(!YandexCDPBridge.isTrustedWebSocketURL(wrongPath, port: port))
        #expect(!YandexCDPBridge.isTrustedWebSocketURL(encryptedRemote, port: port))
    }

    @Test func clipboardRejectsPasswordManagerMarkers() {
        #expect(SystemTextClipboardAdapter.shouldCapture(types: [.string]))
        #expect(!SystemTextClipboardAdapter.shouldCapture(types: [
            .string,
            .init("org.nspasteboard.ConcealedType")
        ]))
        #expect(!SystemTextClipboardAdapter.shouldCapture(types: [
            .string,
            .init("org.nspasteboard.TransientType")
        ]))
    }
}

private final class NotesAdapterDouble: NotesAppAdapter {
    let app: NotesApp
    let isInstalled = true
    let capability = IntegrationCapabilityDeclaration(id: "test.notes")

    init(app: NotesApp) {
        self.app = app
    }

    func openNotes() -> IntegrationResult { .success }
    func createNote() -> IntegrationResult { .success }
}

private final class SystemEventAdapterDouble: SystemEventAdapter {
    let kind: HookySystemEvent.Kind
    let capability = IntegrationCapabilityDeclaration(id: "test.system")
    private(set) var startCount = 0
    private(set) var stopCount = 0

    init(kind: HookySystemEvent.Kind) {
        self.kind = kind
    }

    func start(receive: @escaping (HookySystemEvent) -> Void) {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }
}
