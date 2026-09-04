import Combine
import Foundation

final class IntegrationDiagnosticsStore: ObservableObject {
    @Published private(set) var items: [IntegrationDiagnosticItem] = []
    @Published private(set) var isRefreshing = false

    private let music: MusicStore
    private let notes: NotesStore
    private let tools: ToolsStore
    private let features: SystemFeatureStore
    private let adapter: any IntegrationDiagnosticsAdapter
    private var refreshGeneration = 0

    init(
        music: MusicStore,
        notes: NotesStore,
        tools: ToolsStore,
        features: SystemFeatureStore,
        adapter: any IntegrationDiagnosticsAdapter = SystemIntegrationDiagnosticsAdapter()
    ) {
        self.music = music
        self.notes = notes
        self.tools = tools
        self.features = features
        self.adapter = adapter
    }

    func refresh() {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        isRefreshing = true

        // Снимок настроек берём на главном потоке, а потенциально медленные
        // проверки CDP, GitHub CLI и системных доступов выполняем в фоне.
        let musicSource = music.selectedMusicSource
        let musicAdapter = music.activeAdapter
        let notesApp = notes.selectedApp
        let notesInstalled = notes.isInstalled(notesApp)
        let calendarEnabled = features.calendarEnabled
        let bluetoothEnabled = features.bluetoothEnabled
        let airDropEnabled = features.airDropEnabled
        let developerModeEnabled = tools.developerModeEnabled
        let selectedIDE = tools.selectedIDE
        let selectedIDEInstalled = tools.isDeveloperIDEInstalled(selectedIDE)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }

            let context = IntegrationDiagnosticsContext(
                musicSource: musicSource,
                musicInstalled: self.adapter.isApplicationInstalled(
                    bundleIdentifier: musicSource.bundleIdentifier
                ),
                musicRunning: musicAdapter.isRunning(),
                musicControlChannelAvailable: musicAdapter.controlChannelAvailable(),
                notesApp: notesApp,
                notesInstalled: notesInstalled,
                accessibility: self.adapter.authorization(for: .accessibility),
                calendar: self.adapter.authorization(for: .calendar),
                bluetooth: self.adapter.authorization(for: .bluetooth),
                screenshotsFolder: self.adapter.authorization(for: .desktopFolder),
                downloadsFolder: self.adapter.authorization(for: .downloadsFolder),
                calendarEnabled: calendarEnabled,
                bluetoothEnabled: bluetoothEnabled,
                airDropEnabled: airDropEnabled,
                developerModeEnabled: developerModeEnabled,
                selectedIDE: selectedIDE,
                selectedIDEInstalled: selectedIDEInstalled,
                githubCLIAvailable: self.adapter.isExecutableAvailable(at: [
                    "/opt/homebrew/bin/gh",
                    "/usr/local/bin/gh"
                ])
            )
            let items = IntegrationDiagnosticsBuilder.makeItems(from: context)

            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.refreshGeneration else { return }
                self.items = items
                self.isRefreshing = false
            }
        }
    }

    func openSettings(for item: IntegrationDiagnosticItem) {
        guard let permission = item.settingsPermission else { return }
        adapter.openSystemSettings(for: permission)
    }

    func refreshLocalizedContent() {
        refresh()
    }
}
