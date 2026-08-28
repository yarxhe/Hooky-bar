import SwiftUI

struct SettingsPane: View {
    @ObservedObject var store: MusicStore
    @ObservedObject var notes: NotesStore
    @ObservedObject var tools: ToolsStore
    @ObservedObject var features: SystemFeatureStore
    @ObservedObject var localization: AppLocalization

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                settingsHeader(L10n.tr("settings.language.title"), L10n.tr("settings.language.subtitle"))
                Picker("", selection: Binding(
                    get: { localization.language },
                    set: localization.select
                )) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.pickerTitle).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                Divider()
                settingsHeader(L10n.tr("settings.music.title"), L10n.tr("settings.music.subtitle"))

                HStack(spacing: 12) {
                    ForEach(MusicSource.allCases) { source in
                        Button { store.selectMusicSource(source) } label: {
                            VStack(spacing: 8) {
                                MusicSourceIcon(source: source)
                                    .frame(width: 36, height: 36)
                                Text(source.fullTitle)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                            }
                            .frame(width: 102, height: 78)
                            .background(
                                store.selectedMusicSource == source ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(store.selectedMusicSource == source ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()
                settingsHeader(L10n.tr("settings.notes.title"), L10n.tr("settings.notes.subtitle"))

                HStack(spacing: 12) {
                    ForEach(NotesApp.allCases) { app in
                        Button { notes.select(app) } label: {
                            VStack(spacing: 7) {
                                NotesAppIcon(app: app)
                                    .frame(width: 36, height: 36)
                                Text(app.title)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(notes.isInstalled(app) ? app.subtitle : L10n.tr("settings.notInstalled"))
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 86)
                            .background(
                                notes.selectedApp == app ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(notes.selectedApp == app ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider()
                settingsHeader(L10n.tr("settings.events.title"), L10n.tr("settings.events.subtitle"))

                VStack(spacing: 0) {
                    featureToggle(L10n.tr("settings.bluetooth.title"), L10n.tr("settings.bluetooth.subtitle"), "antenna.radiowaves.left.and.right",
                                  isOn: binding(\.bluetoothEnabled, setter: features.setBluetoothEnabled))
                    Divider().padding(.leading, 38)
                    featureToggle(L10n.tr("settings.vpn.title"), L10n.tr("settings.vpn.subtitle"), "lock.shield",
                                  isOn: binding(\.vpnEnabled, setter: features.setVPNEnabled))
                    Divider().padding(.leading, 38)
                    featureToggle(L10n.tr("settings.airdrop.title"), L10n.tr("settings.airdrop.subtitle"), "airdrop",
                                  isOn: binding(\.airDropEnabled, setter: features.setAirDropEnabled))
                    Divider().padding(.leading, 38)
                    featureToggle(L10n.tr("settings.calendar.title"), L10n.tr("settings.calendar.subtitle"), "calendar",
                                  isOn: binding(\.calendarEnabled, setter: features.setCalendarEnabled))
                }
                .padding(.horizontal, 12)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Divider()
                settingsHeader(L10n.tr("settings.developer.title"), L10n.tr("settings.developer.subtitle"))
                featureToggle(
                    L10n.tr("settings.developerMode.title"),
                    L10n.tr("settings.developerMode.subtitle"),
                    "chevron.left.forwardslash.chevron.right",
                    isOn: Binding(
                        get: { tools.developerModeEnabled },
                        set: tools.setDeveloperModeEnabled
                    )
                )
                .padding(.horizontal, 12)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                if tools.developerModeEnabled {
                    HStack(spacing: 10) {
                        Image(systemName: tools.selectedIDE.symbol)
                            .frame(width: 28)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("settings.ide.title"))
                                .font(.system(size: 12, weight: .medium))
                            Text(
                                tools.isDeveloperIDEInstalled(tools.selectedIDE)
                                    ? L10n.tr("settings.ide.subtitle")
                                    : L10n.tr("settings.notInstalled")
                            )
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Section(L10n.tr("settings.ide.editors")) {
                                ForEach(DeveloperIDE.editors) { ide in
                                    ideSelectionButton(ide)
                                }
                            }
                            Section("JetBrains") {
                                ForEach(DeveloperIDE.jetBrainsIDEs) { ide in
                                    ideSelectionButton(ide)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Text(tools.selectedIDE.title)
                                    .lineLimit(1)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(
                                Color.primary.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.8)
                    }

                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.gearshape")
                            .frame(width: 28)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(L10n.tr("settings.workspace.title")).font(.system(size: 12, weight: .medium))
                            Text(tools.workspace.isConfigured ? tools.workspace.path : L10n.tr("settings.workspace.notSelected"))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button(L10n.tr("settings.workspace.choose"), action: tools.chooseDeveloperWorkspace)
                            .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                HStack(spacing: 10) {
                    Label("GitHub Actions", systemImage: "hammer")
                    Spacer()
                    Text(L10n.tr("settings.githubCLI")).foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
                .padding(12)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(22)
        }
        .frame(width: 430, height: 520, alignment: .topLeading)
        .environment(\.locale, localization.locale)
    }

    private func settingsHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 16, weight: .semibold))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func featureToggle(_ title: String, _ subtitle: String, _ icon: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden()
        }
        .padding(.vertical, 9)
    }

    private func ideSelectionButton(_ ide: DeveloperIDE) -> some View {
        Button {
            tools.selectDeveloperIDE(ide)
        } label: {
            if tools.selectedIDE == ide {
                Label(ide.title, systemImage: "checkmark")
            } else {
                Label(ide.title, systemImage: ide.symbol)
            }
        }
    }

    private func binding(_ keyPath: KeyPath<SystemFeatureStore, Bool>, setter: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: { features[keyPath: keyPath] }, set: setter)
    }
}
