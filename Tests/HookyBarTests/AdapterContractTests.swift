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

    @Test func coldMusicLaunchKeepsOnePlayIntentUntilPlaybackIsConfirmed() async throws {
        let store = MusicStore()
        let adapter = ColdLaunchMusicAdapterDouble(
            source: .spotify,
            mediaController: store.activeAdapter.mediaController,
            failuresBeforeReady: 2
        )
        store.adapterRegistry.register(adapter)
        store.selectedMusicSource = .spotify

        store.togglePlayback()
        try await Task.sleep(for: .seconds(2.5))

        #expect(adapter.launchCount == 1)
        #expect(adapter.startPlaybackCount == 3)
        #expect(store.pendingPlaybackStartToken == nil)
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

    @Test func developerGitSnapshotParsesStablePorcelainState() {
        let status = """
        # branch.oid abc123
        # branch.head feature/dev-panel
        # branch.upstream origin/feature/dev-panel
        # branch.ab +2 -1
        # stash 3
        1 .M N... 100644 100644 100644 abc abc Sources/App.swift
        2 R. N... 100644 100644 100644 abc abc R100 Sources/New.swift\tSources/Old.swift
        u UU N... 100644 100644 100644 100644 abc abc abc Sources/Conflict.swift
        ? Notes.md
        """

        let snapshot = DeveloperToolAdapter.snapshot(
            for: URL(fileURLWithPath: "/tmp/HookyTest", isDirectory: true),
            status: status,
            commit: "abc123  Improve Dev panel"
        )

        #expect(snapshot.branch == "feature/dev-panel")
        #expect(snapshot.changedFiles == 3)
        #expect(snapshot.untrackedFiles == 1)
        #expect(snapshot.ahead == 2)
        #expect(snapshot.behind == 1)
        #expect(snapshot.stashCount == 3)
        #expect(snapshot.lastCommit == "abc123  Improve Dev panel")
    }

    @Test func developerCommandAdapterDetectsSwiftPackageWithoutRunningIt() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("HookyCommandAdapter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let manifest = folder.appendingPathComponent("Package.swift")
        #expect(FileManager.default.createFile(atPath: manifest.path, contents: Data()))

        let adapter = DeveloperCommandAdapter()
        let snapshot = adapter.inspectWorkspace(at: folder)

        #expect(snapshot.toolchain == "Swift")
        #expect(snapshot.availableCommands == Set(DeveloperCommandKind.allCases))
        #expect(snapshot.state == .idle)
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

    @Test func clipboardRetentionKeepsPinsAndBoundsHistory() {
        let now = Date(timeIntervalSince1970: 1_000)
        let policy = ClipboardRetentionPolicy(
            maximumUnpinnedItems: 1,
            maximumAge: 100,
            cleanupInterval: 60
        )
        let items = [
            clipboardItem(id: "latest", createdAt: now.addingTimeInterval(-1)),
            clipboardItem(id: "overflow", createdAt: now.addingTimeInterval(-2)),
            clipboardItem(id: "expired", createdAt: now.addingTimeInterval(-200)),
            clipboardItem(id: "pinned-expired", createdAt: now.addingTimeInterval(-300))
        ]

        let removed = policy.itemsToRemove(
            from: items,
            pinnedIDs: ["pinned-expired"],
            referenceDate: now
        )

        #expect(Set(removed.map(\.id)) == ["overflow", "expired"])
    }

    @Test func integrationDiagnosticsExposeDeniedPermissionWithoutRequestingIt() throws {
        let items = IntegrationDiagnosticsBuilder.makeItems(from: diagnosticsContext(
            calendar: .denied,
            calendarEnabled: true
        ))
        let calendar = try #require(items.first { $0.id == "system.calendar" })

        #expect(calendar.status == .needsAttention)
        #expect(calendar.settingsPermission == .calendar)
    }

    @Test func integrationDiagnosticsKeepDisabledFeaturesInactive() throws {
        let items = IntegrationDiagnosticsBuilder.makeItems(from: diagnosticsContext(
            bluetooth: .denied,
            bluetoothEnabled: false,
            airDropEnabled: false
        ))
        let bluetooth = try #require(items.first { $0.id == "system.bluetooth" })
        let airDrop = try #require(items.first { $0.id == "system.airdrop" })

        #expect(bluetooth.status == .inactive)
        #expect(bluetooth.settingsPermission == nil)
        #expect(airDrop.status == .inactive)
    }

    @Test func yandexDiagnosticsRequireFallbackOnlyWhenControlChannelIsUnavailable() throws {
        let items = IntegrationDiagnosticsBuilder.makeItems(from: diagnosticsContext(
            musicControlChannelAvailable: false,
            accessibility: .notDetermined
        ))
        let controls = try #require(items.first { $0.id == "music.yandex.controls" })

        #expect(controls.status == .checkedOnUse)
        #expect(controls.settingsPermission == .accessibility)
    }

    @Test func diagnosticsReportContainsOnlyShareableEnvironmentState() {
        let items = IntegrationDiagnosticsBuilder.makeItems(from: diagnosticsContext())
        let report = IntegrationDiagnosticsReportBuilder.makeReport(
            items: items,
            appVersion: "1.3.0 (4)",
            operatingSystem: "macOS 15.0",
            generatedAt: Date(timeIntervalSince1970: 0)
        )

        #expect(report.contains("Hooky bar diagnostics"))
        #expect(report.contains("App: 1.3.0 (4)"))
        #expect(report.contains("[ready]"))
        #expect(!report.contains("/Users/"))
        #expect(!report.contains(NSHomeDirectory()))
    }
}

private func clipboardItem(id: String, createdAt: Date) -> ClipboardItem {
    ClipboardItem(
        id: id,
        sourceID: "test.clipboard",
        sourceName: "Tests",
        sourceBundleIdentifier: nil,
        kind: .text,
        text: id,
        fileURL: nil,
        createdAt: createdAt
    )
}

private func diagnosticsContext(
    musicControlChannelAvailable: Bool? = true,
    accessibility: IntegrationAuthorizationState = .granted,
    calendar: IntegrationAuthorizationState = .granted,
    bluetooth: IntegrationAuthorizationState = .granted,
    calendarEnabled: Bool = true,
    bluetoothEnabled: Bool = true,
    airDropEnabled: Bool = true
) -> IntegrationDiagnosticsContext {
    IntegrationDiagnosticsContext(
        musicSource: .yandex,
        musicInstalled: true,
        musicRunning: true,
        musicControlChannelAvailable: musicControlChannelAvailable,
        notesApp: .obsidian,
        notesInstalled: true,
        accessibility: accessibility,
        calendar: calendar,
        bluetooth: bluetooth,
        screenshotsFolder: .granted,
        downloadsFolder: .granted,
        calendarEnabled: calendarEnabled,
        bluetoothEnabled: bluetoothEnabled,
        airDropEnabled: airDropEnabled,
        developerModeEnabled: false,
        selectedIDE: .visualStudioCode,
        selectedIDEInstalled: true,
        githubCLIAvailable: true
    )
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

private final class ColdLaunchMusicAdapterDouble: MusicPlayerAdapter {
    let source: MusicSource
    let mediaController: MediaController
    let capabilities = MusicAdapterCapabilities(
        canLike: false,
        canDislike: false,
        canSeek: false,
        canReadUpcomingTrack: false
    )

    private let lock = NSLock()
    private let failuresBeforeReady: Int
    private var running = false
    private var playing = false
    private var launches = 0
    private var starts = 0

    init(
        source: MusicSource,
        mediaController: MediaController,
        failuresBeforeReady: Int
    ) {
        self.source = source
        self.mediaController = mediaController
        self.failuresBeforeReady = failuresBeforeReady
    }

    var launchCount: Int { locked { launches } }
    var startPlaybackCount: Int { locked { starts } }

    func isRunning() -> Bool { locked { running } }

    func launch() {
        locked {
            launches += 1
            running = true
        }
    }

    func snapshot(from info: TrackInfo) -> MusicAdapterSnapshot? { nil }
    func directSnapshot(context: MusicCommandContext) -> MusicAdapterSnapshot? { nil }
    func playbackState() -> Bool? { locked { playing } }
    func ratingState(context: MusicCommandContext) -> MusicRatingState? { nil }
    func upcomingTrack(context: MusicCommandContext) -> UpcomingTrack? { nil }

    func startPlayback(context: MusicCommandContext) -> MusicAdapterResult {
        locked {
            starts += 1
            guard starts > failuresBeforeReady else {
                return .failure(.adapterUnavailable)
            }
            playing = true
            return .success
        }
    }

    func togglePlayback(context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func nextTrack(context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func previousTrack(context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func seek(to seconds: Double, context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func setLiked(_ desired: Bool, context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }
    func setDisliked(_ desired: Bool, context: MusicCommandContext) -> MusicAdapterResult { .failure(.notSupported) }

    private func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
