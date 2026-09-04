import AppKit
import ApplicationServices
import Combine
import CoreAudio
import Darwin
import ImageIO
import MediaRemoteAdapter
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel!
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let music = MusicStore()
    private let clipboard = ClipboardStore()
    private let notes = NotesStore()
    private let tools = ToolsStore()
    private let volume = VolumeStore()
    private let ui = InterfaceModel()
    private let features = SystemFeatureStore()
    private let localization = AppLocalization()
    private lazy var diagnostics = IntegrationDiagnosticsStore(
        music: music,
        notes: notes,
        tools: tools,
        features: features
    )
    private var subscriptions = Set<AnyCancellable>()
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.applicationIconImage = HookyBrandImages.image(for: .hookyBar)
        configureStatusItem()
        makePanel()
        localization.$language.dropFirst().sink { [weak self] _ in
            guard let self else { return }
            self.refreshLocalizedContent()
        }
        .store(in: &subscriptions)
        installPointerMonitoring()
        ui.shouldRemainExpanded = { [weak self] in self?.pointerInsideInteractiveSurface() ?? false }
        ui.shouldCollapseToCompactPlayer = { [weak self] in
            guard let self else { return false }
            return self.music.compactPlaybackActive || self.features.hasPomodoro
        }
        clipboard.onNewScreenshot = { [weak self] url in self?.ui.presentScreenshot(url) }
        music.startMonitoring()
        clipboard.startMonitoring()
        volume.startMonitoring()
        features.start()
        updateMenuCollision()
        installWorkspaceMonitoring()

        ui.$expanded.removeDuplicates()
        .sink { [weak self] expanded in
            guard let self else { return }
            if expanded {
                self.panel.ignoresMouseEvents = false
                self.presentExpandedPanel()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) { [weak self] in
                    guard let self, !self.ui.expanded else { return }
                    self.panel.ignoresMouseEvents = true
                    (self.panel as? HookyPanel)?.finishExpandedPresentation()
                }
            }
        }
        .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.placePanel()
                self?.updateMenuCollision()
            }
            .store(in: &subscriptions)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspaceCenter.removeObserver)
        workspaceObservers.removeAll()
        music.stopMonitoring()
        clipboard.stopMonitoring()
        volume.stopMonitoring()
        features.stop()
        tools.stop()
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let icon = HookyBrandImages.image(for: .hookyBar)?.copy() as? NSImage {
            icon.size = NSSize(width: 18, height: 18)
            icon.isTemplate = false
            icon.accessibilityDescription = "Hooky bar"
            statusItem.button?.image = icon
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Hooky bar")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L10n.tr("app.menu.open"), action: #selector(openPanel), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: L10n.tr("app.menu.settings"), action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.tr("app.menu.quit"), action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func makePanel() {
        let content = HookyBarView(
            store: music,
            clipboard: clipboard,
            notes: notes,
            tools: tools,
            volume: volume,
            ui: ui,
            features: features,
            localization: localization
        )
        panel = makeFloatingPanel(content: NSHostingView(rootView: content))
        placePanel()
        panel.ignoresMouseEvents = true
    }

    private func makeFloatingPanel(content: NSView) -> NSPanel {
        let result = HookyPanel(contentRect: .zero,
                                styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered,
                                defer: false)
        result.isFloatingPanel = true
        result.level = .statusBar
        result.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        result.backgroundColor = .clear
        result.isOpaque = false
        result.hasShadow = false
        result.hidesOnDeactivate = false
        result.becomesKeyOnlyIfNeeded = false
        result.isMovable = false
        result.acceptsMouseMovedEvents = true
        result.ignoresMouseEvents = false
        result.contentView = content
        return result
    }

    private func placePanel() {
        guard let panel, let screen = screenContainingNotch() else { return }
        let notchWidth: CGFloat
        if screen.safeAreaInsets.top > 0,
           let rightArea = screen.auxiliaryTopRightArea,
           let leftArea = screen.auxiliaryTopLeftArea {
            notchWidth = max(180, rightArea.minX - leftArea.maxX)
            ui.notchHeight = max(30, screen.safeAreaInsets.top)
        } else {
            notchWidth = 200
            ui.notchHeight = 32
        }
        ui.notchWidth = notchWidth
        let targetHeight: CGFloat = 314
        let target = NSRect(x: screen.frame.midX - 220,
                            y: screen.frame.maxY - targetHeight,
                            width: 440,
                            height: targetHeight)
        panel.orderFrontRegardless()
        panel.setFrame(target, display: true)
        panel.alphaValue = 1
        panel.hasShadow = false
    }

    private func installPointerMonitoring() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            DispatchQueue.main.async { self?.handleGlobalPointerMove() }
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler)
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.handleGlobalPointerMove()
            return event
        }
    }

    private func installWorkspaceMonitoring() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.updateMenuCollision()
            }
        ]
    }

    private func handleGlobalPointerMove() {
        guard !ui.expanded, let panel else { return }
        let layout = currentSurfaceLayout
        let surface = NSRect(
            x: panel.frame.midX - layout.width / 2 + layout.horizontalOffset,
            y: panel.frame.maxY - layout.height,
            width: layout.width,
            height: layout.height
        )
        if surface.contains(NSEvent.mouseLocation) {
            panel.ignoresMouseEvents = false
            ui.pointerInside(true)
        }
    }

    /// Прозрачная неактивная NSPanel может держать старый compositor snapshot.
    /// Обновляем backing view после того, как SwiftUI вставил раскрытый контент,
    /// не делая панель key window и не отбирая фокус у текущего приложения.
    private func refreshPanelRendering() {
        guard let contentView = panel.contentView else { return }
        contentView.needsLayout = true
        contentView.needsDisplay = true
        DispatchQueue.main.async { [weak contentView, weak panel] in
            contentView?.layoutSubtreeIfNeeded()
            contentView?.layer?.setNeedsDisplay()
            contentView?.displayIfNeeded()
            panel?.displayIfNeeded()
        }
    }

    private func presentExpandedPanel() {
        guard let hookyPanel = panel as? HookyPanel else {
            refreshPanelRendering()
            return
        }

        // SwiftUI сначала публикует expanded, затем вставляет glass-иерархию.
        // На следующем run loop делаем уже видимую non-activating панель key:
        // это тот же переход, который раньше случайно происходил первым кликом.
        DispatchQueue.main.async { [weak self, weak hookyPanel] in
            guard let self, let hookyPanel, self.ui.expanded else { return }
            hookyPanel.prepareForExpandedPresentation()
            self.refreshPanelRendering()
        }
    }

    private func screenContainingNotch() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func pointerInsideInteractiveSurface() -> Bool {
        guard let panel else { return false }
        let layout = currentSurfaceLayout
        let surface = NSRect(x: panel.frame.midX - layout.width / 2 + layout.horizontalOffset,
                             y: panel.frame.maxY - layout.height,
                             width: layout.width,
                             height: layout.height)
        return surface.contains(NSEvent.mouseLocation)
    }

    @objc private func openPanel() {
        ui.setExpanded(true)
    }

    @objc private func openSettings() {
        diagnostics.refresh()
        if settingsWindow == nil {
            let content = NSHostingView(rootView: SettingsPane(
                store: music,
                notes: notes,
                tools: tools,
                features: features,
                localization: localization,
                diagnostics: diagnostics
            ))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 430, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.tr("settings.window.title")
            window.contentView = content
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func updateMenuCollision() {
        guard let screen = screenContainingNotch() else { return }
        let notchLeft = screen.frame.midX - ui.notchWidth / 2
        let shouldHide = MenuBarCollisionDetector.shouldHideLeftWing(notchLeft: notchLeft)
        if ui.hideLeftMusicWing != shouldHide { ui.hideLeftMusicWing = shouldHide }
    }

    private func refreshLocalizedContent() {
        let items = statusItem.menu?.items ?? []
        if items.indices.contains(0) { items[0].title = L10n.tr("app.menu.open") }
        if items.indices.contains(1) { items[1].title = L10n.tr("app.menu.settings") }
        if items.indices.contains(3) { items[3].title = L10n.tr("app.menu.quit") }
        settingsWindow?.title = L10n.tr("settings.window.title")
        music.refreshLocalizedContent()
        notes.refreshLocalizedContent()
        tools.refreshLocalizedContent()
        diagnostics.refreshLocalizedContent()
    }

    private var hasCompactContent: Bool {
        music.compactPlaybackActive || features.hasPomodoro
    }

    private var currentSurfaceLayout: HookySurfaceLayout {
        ui.surfaceLayout(
            hasCompactContent: hasCompactContent,
            systemEventID: features.currentEvent?.id
        )
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
