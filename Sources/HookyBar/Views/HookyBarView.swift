import Cocoa
import SwiftUI

struct HookyBarView: View {
    @StateObject private var paneCache = NativePaneCache()
    @ObservedObject var store: MusicStore
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var notes: NotesStore
    @ObservedObject var tools: ToolsStore
    @ObservedObject var volume: VolumeStore
    @ObservedObject var ui: InterfaceModel
    @ObservedObject var features: SystemFeatureStore
    @ObservedObject var localization: AppLocalization

    var body: some View {
        NativeSurface(surface: surfaceLayout,
                      backgroundOpacity: isIdle && !ui.collapseSurfaceVisible ? 0.001 : 1,
                      contentRevision: surfaceContentRevision,
                      onHover: { ui.pointerInside($0) }) {
            Group {
                if ui.screenshotPreview != nil, ui.contentExpanded {
                    expandedContent
                        .frame(width: 380, height: 250, alignment: .top)
                } else if ui.showScreenshotSuccess {
                    screenshotSuccess
                } else if ui.screenshotPreview != nil {
                    collapsedContent
                } else {
                    musicTransitionContent
                }
            }
            .frame(width: surfaceLayout.width, alignment: .top)
            .frame(height: surfaceLayout.height, alignment: .top)
            .foregroundStyle(Color.white)
            .contentShape(Rectangle())
            .offset(x: surfaceLayout.horizontalOffset)
            .animation(HookyMotion.compactWingResize, value: ui.compactLeadingWingWidth)
            .animation(HookyMotion.compactWingResize, value: ui.compactTrailingWingWidth)
        }
        .frame(width: 440)
        .frame(height: 314, alignment: .top)
        .clipped()
        .onChange(of: tools.developerModeEnabled) { _, enabled in
            if !enabled, ui.tab == 3 {
                ui.selectTab(2)
            }
        }
        .onAppear { store.setSpectrumPresentationActive(visualizerPresentationActive) }
        .onChange(of: visualizerPresentationActive) { _, active in
            store.setSpectrumPresentationActive(active)
        }
        .onDisappear { store.setSpectrumPresentationActive(false) }
        // Keep controls active even when another application has keyboard focus.
        .environment(\.controlActiveState, .active)
        .environment(\.locale, localization.locale)
    }

    private var surfaceLayout: HookySurfaceLayout {
        ui.surfaceLayout(
            hasCompactContent: hasCompactContent,
            systemEventID: features.currentEvent?.id
        )
    }

    /// The nested host observes its own stores. Reinstall its root only when
    /// shell/header structure changes, not for every playback-clock publication.
    private var surfaceContentRevision: AnyHashable {
        var hasher = Hasher()
        hasher.combine(ui.expanded)
        hasher.combine(ui.contentExpanded)
        hasher.combine(ui.tab)
        hasher.combine(ui.screenshotPreview)
        hasher.combine(ui.showScreenshotSuccess)
        hasher.combine(ui.compactLeadingWingWidth)
        hasher.combine(ui.compactTrailingWingWidth)
        hasher.combine(store.compactPlaybackActive)
        hasher.combine(store.nowPlaying.isPlaying)
        hasher.combine(store.audioActive)
        hasher.combine(store.systemSpectrumEnabled)
        hasher.combine(store.selectedMusicSource)
        hasher.combine(store.trackPresentationRevision)
        hasher.combine(store.artworkPresentationRevision)
        hasher.combine(store.upcomingTrack?.title)
        hasher.combine(store.upcomingTrack?.artist)
        hasher.combine(clipboard.screenshotCount)
        hasher.combine(clipboard.textCount)
        hasher.combine(features.currentEvent?.id)
        hasher.combine(features.hasPomodoro)
        hasher.combine(tools.developerModeEnabled)
        hasher.combine(tools.workspace.branch)
        hasher.combine(localization.locale.identifier)
        return AnyHashable(hasher.finalize())
    }

    private var isIdle: Bool {
        surfaceLayout.isIdle
    }

    private var hasCompactContent: Bool {
        store.compactPlaybackActive || features.hasPomodoro
    }

    private var visualizerPresentationActive: Bool {
        guard ui.screenshotPreview == nil else { return false }
        if ui.expanded { return ui.tab == 0 && store.nowPlaying.isPlaying }
        return store.compactPlaybackActive && ui.compactTrailingWingWidth > 8
    }

    private var compactSurfaceWidth: CGFloat {
        ui.surfaceLayout(
            hasCompactContent: true,
            systemEventID: features.currentEvent?.id
        ).width
    }

    private var musicTransitionContent: some View {
        ZStack(alignment: .top) {
            if ui.expanded {
                expandedContent
                    // Animate the outer shell while the live page keeps its
                    // final layout. Avoid reflowing every control as it opens.
                    .frame(width: 440, height: 314, alignment: .top)
                    .transition(.opacity)
            } else {
                collapsedContent
                    .transition(.opacity)
                    .gesture(panelDrag)
            }
        }
        .animation(HookyMotion.contentFade, value: ui.expanded)
    }

    private var collapsedContent: some View {
        Group {
            if isIdle {
                Color.black.opacity(0.001)
            } else {
                VStack(spacing: 0) {
                    // Верх и нижнее уведомление принадлежат одной поверхности.
                    // Высота общего контейнера раскрывает строку снизу без второй move-анимации.
                    compactBarContent(suppressIdleChrome: features.currentEvent != nil)

                    if let event = features.currentEvent {
                        SystemEventBanner(event: event, width: compactSurfaceWidth)
                    }
                }
            }
        }
    }

    /// Во время системного события верхняя часть остаётся настоящим mini-player chrome.
    /// Событие рисуется только в banner снизу и больше не дублируется в крыльях.
    private func compactBarContent(suppressIdleChrome: Bool = false) -> some View {
        HStack(spacing: 0) {
            Group {
                if features.hasPomodoro {
                    PomodoroCompactTime(features: features)
                } else if store.compactPlaybackActive || !suppressIdleChrome {
                    Group {
                        if let artwork = store.nowPlaying.artwork {
                            Image(nsImage: artwork).resizable().scaledToFill()
                        } else {
                            MusicSourceIcon(source: store.selectedMusicSource)
                        }
                    }
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Color.clear
                }
            }
            .frame(width: ui.compactLeadingWingWidth, height: ui.notchHeight)
            .opacity(ui.compactLeadingWingWidth > 0 ? 1 : 0)
            .clipped()

            Color.clear.frame(width: ui.notchWidth, height: ui.notchHeight)

            Group {
                if store.compactPlaybackActive {
                    CompactSpectrumView(signal: store.spectrumSignal, colors: store.visualizerColors,
                                        active: !ui.expanded && store.compactPlaybackActive
                                            && ui.compactTrailingWingWidth > 8,
                                        simulated: store.usesSimulatedSpectrum)
                        .frame(width: max(0, ui.compactTrailingWingWidth - 8), height: 19)
                } else if features.hasPomodoro {
                    PomodoroCompactProgress(progress: features.pomodoroProgress, running: features.pomodoroRunning)
                } else if suppressIdleChrome {
                    Color.clear
                } else {
                    PomodoroCompactProgress(progress: features.pomodoroProgress, running: features.pomodoroRunning)
                }
            }
            .frame(width: ui.compactTrailingWingWidth, height: ui.notchHeight)
            .opacity(ui.compactTrailingWingWidth > 0 ? 1 : 0)
            .clipped()
        }
        .frame(width: compactSurfaceWidth, height: ui.notchHeight)
    }

    private var screenshotSuccess: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 25, height: 25)
            .background(Color.green, in: Circle())
            .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private var expandedContent: some View {
        ZStack {
            if ui.screenshotPreview == nil, ui.tab == 0 {
                LiquidEtherBackground(
                    colors: store.visualizerColors,
                    active: ui.expanded && (store.nowPlaying.isPlaying || store.audioActive)
                )
            }

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    expandedHeaderLeading
                        .frame(width: 112, alignment: .leading)
                    Spacer()
                    if ui.screenshotPreview == nil {
                        SpectrumView(signal: store.spectrumSignal, colors: store.visualizerColors,
                                     active: ui.expanded && ui.tab == 0
                                        && (store.nowPlaying.isPlaying || store.audioActive),
                                     expanded: true,
                                     simulated: store.usesSimulatedSpectrum)
                            .frame(width: 104, height: 18).frame(width: 112)
                    } else {
                        Color.clear.frame(width: 112)
                    }
                }
                .padding(.horizontal, 9).frame(height: ui.notchHeight + 7)
                .contentShape(Rectangle())
                .gesture(panelDrag)

                if let preview = ui.screenshotPreview {
                    ScreenshotCapturePane(url: preview) {
                        clipboard.copyScreenshot(at: preview)
                        ui.screenshotCopied()
                    }
                } else {
                    HStack(spacing: 5) {
                        tabButton(L10n.tr("tab.music"), 0, "music.note")
                        tabButton(L10n.tr("tab.clipboard"), 1, "rectangle.on.rectangle.angled")
                        tabButton(L10n.tr("tab.tools"), 2, "square.grid.2x2")
                        if tools.developerModeEnabled {
                            tabButton(L10n.tr("tab.developer"), 3, "hammer")
                        }
                    }
                    .frame(height: 30)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 9)
                    .zIndex(1)

                    NativePaneTransition(selection: ui.tab, direction: ui.tabDirection, cache: paneCache) {
                        selectedPane
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                }
            }
        }
    }

    // Только шапка управляет раскрытием: жест не конкурирует со ScrollView.
    private var panelDrag: some Gesture {
        DragGesture(minimumDistance: 8).onEnded { value in
            if value.translation.height > 12 { ui.setExpanded(true) }
            if value.translation.height < -12 { ui.setExpanded(false) }
        }
    }

    @ViewBuilder
    private var selectedPane: some View {
        if ui.tab == 0 { MusicPane(store: store, volume: volume) }
        else if ui.tab == 1 { ClipboardPane(clipboard: clipboard) }
        else if ui.tab == 2 {
            ToolsPane(notes: notes, features: features, tools: tools)
        }
        else { DeveloperPane(tools: tools) }
    }

    @ViewBuilder
    private var expandedHeaderLeading: some View {
        if ui.screenshotPreview != nil {
            Image(systemName: "camera.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.78))
        } else if ui.tab == 0 {
            if let next = store.upcomingTrack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(next.title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.82))
                    Text(next.artist).font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.42))
                }
                .lineLimit(1)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.tr("music.nextTrack")).font(.system(size: 9, weight: .semibold))
                    Text(L10n.tr("music.queueUnavailable")).font(.system(size: 8, weight: .medium))
                }
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
            }
        } else if ui.tab == 1 {
            HStack(spacing: 8) {
                headerCounter(icon: "photo.fill", count: clipboard.screenshotCount)
                headerCounter(icon: "list.clipboard.fill", count: clipboard.textCount)
            }
        } else if ui.tab == 2 {
            HStack(spacing: 5) {
                Image(systemName: features.hasPomodoro ? "timer" : "scope")
                PomodoroHeaderLabel(features: features)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.68))
        } else {
            HStack(spacing: 5) {
                Image(systemName: "hammer.fill")
                Text(tools.workspace.isConfigured ? tools.workspace.branch : "Dev")
                    .lineLimit(1)
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.68))
        }
    }

    private func headerCounter(icon: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
            Text("\(count)")
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.68))
    }


    private func tabButton(_ title: String, _ value: Int, _ icon: String) -> some View {
        let selected = ui.tab == value
        return Button {
            guard value != ui.tab else { return }
            HookyDiagnostics.control("action=tab_select phase=request target=\(value)")
            ui.selectTab(value)
            HookyDiagnostics.control("action=tab_select phase=applied target=\(value)")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 15, height: 15)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.48))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .hookyMaterial(
                enabled: selected,
                cornerRadius: 9
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("hooky.tab.\(value)")
        .accessibilityValue(selected ? "selected" : "unselected")
        .frame(maxWidth: .infinity)
    }
}
