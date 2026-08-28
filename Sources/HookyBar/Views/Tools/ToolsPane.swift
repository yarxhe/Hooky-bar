import SwiftUI

struct ToolsPane: View {
    @ObservedObject var notes: NotesStore
    @ObservedObject var features: SystemFeatureStore
    @ObservedObject var tools: ToolsStore

    private let durations = [25, 30, 45]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            timerCard
            quickActions
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 11)
    }

    private var timerCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Label(L10n.tr("tools.timer"), systemImage: "timer")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                keepAwakeControl
                Text(pomodoroTime)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(features.pomodoroRunning ? Color.red : .white.opacity(0.78))
            }

            HStack(spacing: 6) {
                ForEach(durations, id: \.self) { minutes in
                    Button { features.setPomodoroDuration(minutes: minutes) } label: {
                        Text(L10n.tr("tools.minutes.format", minutes))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: 24)
                            .background(
                                features.pomodoroSelectedMinutes == minutes
                                    ? Color.white.opacity(0.16) : .white.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(features.pomodoroSelectedMinutes == minutes
                                        ? .white.opacity(0.24) : .white.opacity(0.07), lineWidth: 0.7))
                    }
                    .buttonStyle(SpringPressButtonStyle())
                }
            }

            HStack(spacing: 7) {
                Button {
                    features.pomodoroRunning ? features.pausePomodoro() : features.startPomodoro()
                } label: {
                    Label(primaryTimerTitle, systemImage: features.pomodoroRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(SpringPressButtonStyle())

                compactControl("arrow.counterclockwise", help: L10n.tr("tools.timer.reset")) {
                    features.resetPomodoro()
                }

            }
        }
        .padding(10)
        .hookyGlass(cornerRadius: 13)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.tr("tools.quickAccess"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer()
                if let status = notes.status {
                    Text(status).font(.system(size: 8, weight: .semibold)).foregroundStyle(.red.opacity(0.8))
                } else {
                    HStack(spacing: 4) {
                        NotesAppIcon(app: notes.selectedApp)
                            .frame(width: 11, height: 11)
                        Text(notes.selectedApp.title)
                    }
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }

            HStack(spacing: 6) {
                quickButton(L10n.tr("tools.myNotes"), "note.text", action: notes.openNotes)
                quickButton(L10n.tr("tools.newNote"), "square.and.pencil", action: notes.createNote)
                quickButton(L10n.tr("tools.calendar"), "calendar", action: tools.openCalendar)
                quickButton(L10n.tr("tools.downloads"), "arrow.down.circle", action: tools.openDownloads)
            }
        }
    }

    private var primaryTimerTitle: String {
        if features.pomodoroRunning { return L10n.tr("tools.timer.pause") }
        return features.pomodoroRemaining < features.pomodoroDuration
            ? L10n.tr("tools.timer.resume") : L10n.tr("tools.timer.start")
    }

    private var keepAwakeControl: some View {
        Button(action: tools.toggleKeepAwake) {
            HStack(spacing: 4) {
                Image(systemName: "display")
                    .font(.system(size: 9, weight: .semibold))
                Text(L10n.tr("tools.display"))
                    .font(.system(size: 8.5, weight: .bold))
                Circle()
                    .fill(tools.keepsMacAwake ? Color.green : .white.opacity(0.25))
                    .frame(width: 5, height: 5)
            }
            .foregroundStyle((tools.keepsMacAwake ? Color.green : .white).opacity(0.9))
            .padding(.horizontal, 7)
            .frame(height: 24)
            .background(
                (tools.keepsMacAwake ? Color.green : .white).opacity(tools.keepsMacAwake ? 0.12 : 0.07),
                in: Capsule()
            )
            .contentShape(Capsule())
        }
        .buttonStyle(SpringPressButtonStyle())
        .help(tools.keepsMacAwake ? L10n.tr("tools.keepAwake.on") : L10n.tr("tools.keepAwake.off"))
    }

    private var pomodoroTime: String {
        let seconds = max(0, Int(features.pomodoroRemaining.rounded(.up)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func compactControl(
        _ symbol: String,
        tint: Color = .white,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint.opacity(0.9))
                .frame(width: 38, height: 34)
                .background(tint.opacity(tint == .white ? 0.07 : 0.12),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(SpringPressButtonStyle())
        .help(help)
    }

    private func quickButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 13, weight: .medium))
                Text(title).font(.system(size: 8.5, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(.white.opacity(0.84))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .hookyGlass(cornerRadius: 10, interactive: true)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(SpringPressButtonStyle())
    }

}
