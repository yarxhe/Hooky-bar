import Cocoa
import SwiftUI

struct HookyBarView: View {
    @ObservedObject var store: MusicStore
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var notes: NotesStore
    @ObservedObject var tools: ToolsStore
    @ObservedObject var volume: VolumeStore
    @ObservedObject var ui: InterfaceModel
    @ObservedObject var features: SystemFeatureStore
    @ObservedObject var localization: AppLocalization

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if ui.screenshotPreview != nil, ui.contentExpanded {
                    expandedContent
                } else if ui.showScreenshotSuccess {
                    screenshotSuccess
                } else if ui.screenshotPreview != nil {
                    collapsedContent
                } else if features.currentEvent != nil, !ui.expanded {
                    systemEventContent
                } else {
                    musicTransitionContent
                }
            }
            .frame(width: surfaceLayout.width, alignment: .top)
            .frame(height: surfaceLayout.height, alignment: .top)
            .background(surfaceBackground)
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: surfaceLayout.bottomLeadingRadius,
                bottomTrailingRadius: surfaceLayout.bottomTrailingRadius,
                topTrailingRadius: 0
            ))
            .foregroundStyle(Color.white)
            .contentShape(Rectangle())
            .onHover { ui.pointerInside($0) }
            .gesture(DragGesture(minimumDistance: 8).onEnded { value in
                if value.translation.height > 12 { ui.setExpanded(true) }
                if value.translation.height < -12 { ui.setExpanded(false) }
            })
            .offset(x: surfaceLayout.horizontalOffset)
            .animation(surfaceAnimation, value: ui.expanded)
            .animation(HookyMotion.collapseToIdle, value: ui.collapseSurfaceVisible)
        }
        .frame(width: 440)
        .frame(height: 314, alignment: .top)
        .clipped()
        .onChange(of: tools.developerModeEnabled) { _, enabled in
            if !enabled, ui.tab == 3 {
                ui.selectTab(2)
            }
        }
        .hookyGlassRevision(ui.glassRevision)
        .environment(\.locale, localization.locale)
    }

    private var surfaceLayout: HookySurfaceLayout {
        ui.surfaceLayout(
            hasCompactContent: hasCompactContent,
            systemEventID: features.currentEvent?.id
        )
    }

    private var surfaceAnimation: Animation {
        switch surfaceLayout.mode {
        case .compact, .systemEvent:
            return HookyMotion.collapseToCompact
        default:
            return hasCompactContent ? HookyMotion.collapseToCompact : HookyMotion.collapseToIdle
        }
    }

    private var surfaceBackground: Color {
        return isIdle && !ui.collapseSurfaceVisible ? Color.black.opacity(0.001) : .black
    }

    private var isIdle: Bool {
        surfaceLayout.isIdle
    }

    private var hasCompactContent: Bool {
        store.compactPlaybackActive || features.hasPomodoro
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
                    .transition(.opacity)
            } else {
                collapsedContent
                    .transition(.opacity)
            }
        }
        .animation(HookyMotion.contentFade, value: ui.expanded)
    }

    private var collapsedContent: some View {
        Group {
            if isIdle {
                Color.black.opacity(0.001)
            } else {
                compactBarContent()
            }
        }
    }

    private var systemEventContent: some View {
        Group {
            if let event = features.currentEvent {
                VStack(spacing: 0) {
                    compactBarContent(event: event)

                    HStack(spacing: 10) {
                        if hasCompactContent {
                            systemEventBadge(event)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.system(size: 11, weight: .semibold))
                                .lineLimit(1)
                            Text(event.subtitle)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white.opacity(0.58))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 13)
                    .frame(width: compactSurfaceWidth, height: 40)
                    .transition(.opacity)
                }
            }
        }
        .frame(width: compactSurfaceWidth, height: ui.notchHeight + 46, alignment: .top)
    }

    private func compactBarContent(event: HookySystemEvent? = nil) -> some View {
        HStack(spacing: 0) {
            if !ui.hideLeftMusicWing {
                Group {
                    if features.hasPomodoro {
                        PomodoroCompactTime(remaining: features.pomodoroRemaining)
                    } else if store.compactPlaybackActive || event == nil {
                        Group {
                            if let artwork = store.nowPlaying.artwork {
                                Image(nsImage: artwork).resizable().scaledToFill()
                            } else {
                                MusicSourceIcon(source: store.selectedMusicSource)
                            }
                        }
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else if let event {
                        systemEventBadge(event)
                    }
                }
                .frame(width: 56, height: ui.notchHeight)
            }

            Color.clear.frame(width: ui.notchWidth, height: ui.notchHeight)

            Group {
                if store.compactPlaybackActive {
                    CompactSpectrumView(signal: store.spectrumSignal, colors: store.visualizerColors,
                                        active: !ui.expanded && store.compactPlaybackActive)
                        .frame(width: 48, height: 19)
                } else if features.hasPomodoro {
                    PomodoroCompactProgress(progress: features.pomodoroProgress, running: features.pomodoroRunning)
                } else if let event {
                    if ui.hideLeftMusicWing {
                        systemEventBadge(event)
                    } else {
                        Text(event.kind == .vpn ? "VPN" : event.title)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                    }
                } else {
                    PomodoroCompactProgress(progress: features.pomodoroProgress, running: features.pomodoroRunning)
                }
            }
            .frame(width: 56, height: ui.notchHeight)
        }
        .frame(width: compactSurfaceWidth, height: ui.notchHeight)
        .background(Color.black)
    }

    private func systemEventBadge(_ event: HookySystemEvent) -> some View {
        Image(systemName: event.symbol)
            .font(.system(size: 14, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(eventIconColor(event))
            .frame(width: 26, height: 26)
            .background(eventIconColor(event).opacity(0.16), in: Circle())
            .symbolEffect(.bounce, value: event.id)
    }

    private func eventIconColor(_ event: HookySystemEvent) -> Color {
        Color(nsColor: event.tint)
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
        HookyGlassContainer(spacing: 8) {
            ZStack {
                if ui.screenshotPreview == nil, ui.tab == 0 {
                    LiquidEtherBackground(
                        colors: store.visualizerColors,
                        active: ui.expanded
                    )
                    .id(store.trackPresentationRevision)
                    .transition(.opacity)
                    .animation(HookyMotion.backgroundPalette, value: store.trackPresentationRevision)
                }

                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        expandedHeaderLeading
                            .frame(width: 112, alignment: .leading)
                        Spacer()
                        if ui.screenshotPreview == nil {
                            SpectrumView(signal: store.spectrumSignal, colors: store.visualizerColors,
                                         active: ui.expanded && (store.nowPlaying.isPlaying || store.audioActive),
                                         expanded: true)
                                .frame(width: 104, height: 18).frame(width: 112)
                        } else {
                            Color.clear.frame(width: 112)
                        }
                    }
                    .padding(.horizontal, 9).frame(height: ui.notchHeight + 7)

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
                        .padding(.horizontal, 12).padding(.bottom, 9)

                        ZStack {
                            selectedPane
                                .id(ui.tab)
                                .transition(tabTransition)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var selectedPane: some View {
        if ui.tab == 0 { MusicPane(store: store, volume: volume) }
        else if ui.tab == 1 { ClipboardPane(clipboard: clipboard) }
        else if ui.tab == 2 { ToolsPane(notes: notes, features: features, tools: tools) }
        else { DeveloperPane(tools: tools) }
    }

    private var tabTransition: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: HookyTabTransitionModifier(horizontalOffset: ui.tabDirection * 18, opacity: 0),
                identity: HookyTabTransitionModifier(horizontalOffset: 0, opacity: 1)
            ),
            removal: .modifier(
                active: HookyTabTransitionModifier(horizontalOffset: ui.tabDirection * -12, opacity: 0),
                identity: HookyTabTransitionModifier(horizontalOffset: 0, opacity: 1)
            )
        )
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
                Text(features.hasPomodoro ? compactPomodoroTime : L10n.tr("tab.tools"))
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

    private var compactPomodoroTime: String {
        let seconds = max(0, Int(features.pomodoroRemaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
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
            ui.selectTab(value)
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
            .hookyGlass(
                enabled: selected,
                cornerRadius: 9,
                interactive: true
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
