import AppKit

extension SystemFeatureStore {
    func startPomodoroClock() {
        pomodoroTimer?.invalidate()
        pomodoroTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.updatePomodoroTime() }
        updatePomodoroTime()
    }

    func updatePomodoroTime() {
        guard let end = pomodoroEndDate else { return }
        pomodoroRemaining = max(0, end.timeIntervalSinceNow)
        if pomodoroRemaining <= 0 {
            pomodoroTimer?.invalidate()
            pomodoroTimer = nil
            pomodoroEndDate = nil
            pomodoroRunning = false
            enqueue(HookySystemEvent(kind: .pomodoro, title: L10n.tr("event.pomodoro.finished"), subtitle: L10n.tr("event.pomodoro.break"), symbol: "timer.circle.fill", tint: .systemRed, deduplicationKey: "pomodoro-finished"))
            pomodoroRemaining = pomodoroDuration
        }
    }

}
