import AppKit
import SwiftUI

struct HookySystemEvent: Identifiable, Equatable {
    enum Kind: Hashable {
        case bluetooth, vpn, calendar, airDrop, pomodoro
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let subtitle: String
    let symbol: String
    let tint: NSColor
    let deduplicationKey: String
}

final class SystemFeatureStore: ObservableObject {
    @Published var currentEvent: HookySystemEvent?
    @Published var pomodoroRemaining: TimeInterval = 25 * 60
    @Published var pomodoroDuration: TimeInterval = 25 * 60
    @Published var pomodoroRunning = false
    @Published var calendarEnabled: Bool
    @Published var bluetoothEnabled: Bool
    @Published var vpnEnabled: Bool
    @Published var airDropEnabled: Bool

    var hasPomodoro: Bool { pomodoroRunning || pomodoroRemaining < pomodoroDuration }
    var pomodoroProgress: Double {
        guard pomodoroDuration > 0 else { return 0 }
        return min(1, max(0, 1 - pomodoroRemaining / pomodoroDuration))
    }
    var pomodoroSelectedMinutes: Int { Int(pomodoroDuration / 60) }

    var eventQueue: [HookySystemEvent] = []
    var eventDismissal: DispatchWorkItem?
    var recentEvents: [String: Date] = [:]
    var pomodoroTimer: Timer?
    var pomodoroEndDate: Date?
    private var eventAdapters: [HookySystemEvent.Kind: any SystemEventAdapter] = [:]

    init() {
        let defaults = UserDefaults.standard
        let hasExistingProfile = defaults.object(forKey: "notes.selectedApp") != nil
            || defaults.object(forKey: "feature.calendar") != nil
            || defaults.object(forKey: "HookyBar.clipboard.pinnedIDs") != nil
        let initialBluetoothEnabled = defaults.object(forKey: "feature.bluetooth") as? Bool ?? hasExistingProfile
        let initialAirDropEnabled = defaults.object(forKey: "feature.airdrop") as? Bool ?? hasExistingProfile
        calendarEnabled = defaults.bool(forKey: "feature.calendar")
        bluetoothEnabled = initialBluetoothEnabled
        vpnEnabled = defaults.object(forKey: "feature.vpn") as? Bool ?? true
        airDropEnabled = initialAirDropEnabled
        let storedMinutes = defaults.integer(forKey: "focus.durationMinutes")
        let selectedMinutes = [25, 30, 45].contains(storedMinutes) ? storedMinutes : 25
        pomodoroDuration = TimeInterval(selectedMinutes * 60)
        pomodoroRemaining = TimeInterval(selectedMinutes * 60)
        if defaults.object(forKey: "feature.bluetooth") == nil {
            defaults.set(initialBluetoothEnabled, forKey: "feature.bluetooth")
        }
        if defaults.object(forKey: "feature.airdrop") == nil {
            defaults.set(initialAirDropEnabled, forKey: "feature.airdrop")
        }
        [
            BluetoothEventAdapter(),
            VPNEventAdapter(),
            CalendarEventAdapter(),
            AirDropEventAdapter()
        ].forEach(register)
    }

    func start() {
        if bluetoothEnabled { startAdapter(.bluetooth) }
        if vpnEnabled { startAdapter(.vpn) }
        if airDropEnabled { startAdapter(.airDrop) }
        if calendarEnabled { startAdapter(.calendar) }
    }

    func stop() {
        eventDismissal?.cancel()
        pomodoroTimer?.invalidate()
        eventAdapters.values.forEach { $0.stop() }
    }

    func setBluetoothEnabled(_ enabled: Bool) {
        bluetoothEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "feature.bluetooth")
        setAdapter(.bluetooth, enabled: enabled)
    }

    func setVPNEnabled(_ enabled: Bool) {
        vpnEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "feature.vpn")
        setAdapter(.vpn, enabled: enabled)
    }

    func setAirDropEnabled(_ enabled: Bool) {
        airDropEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "feature.airdrop")
        setAdapter(.airDrop, enabled: enabled)
    }

    func setCalendarEnabled(_ enabled: Bool) {
        calendarEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "feature.calendar")
        setAdapter(.calendar, enabled: enabled)
    }

    func register(_ adapter: any SystemEventAdapter) {
        eventAdapters[adapter.kind]?.stop()
        eventAdapters[adapter.kind] = adapter
    }

    var systemCapabilities: [IntegrationCapabilityDeclaration] {
        eventAdapters.values.map(\.capability).sorted { $0.id < $1.id }
    }

    private func setAdapter(_ kind: HookySystemEvent.Kind, enabled: Bool) {
        enabled ? startAdapter(kind) : eventAdapters[kind]?.stop()
    }

    private func startAdapter(_ kind: HookySystemEvent.Kind) {
        eventAdapters[kind]?.start { [weak self] event in
            DispatchQueue.main.async { self?.enqueue(event) }
        }
    }

    func startPomodoro() {
        if pomodoroRemaining <= 0 || pomodoroRemaining > pomodoroDuration {
            pomodoroRemaining = pomodoroDuration
        }
        pomodoroEndDate = Date().addingTimeInterval(pomodoroRemaining)
        pomodoroRunning = true
        startPomodoroClock()
    }

    func pausePomodoro() {
        updatePomodoroTime()
        pomodoroEndDate = nil
        pomodoroRunning = false
    }

    func resetPomodoro() {
        pomodoroTimer?.invalidate()
        pomodoroTimer = nil
        pomodoroEndDate = nil
        pomodoroRunning = false
        pomodoroRemaining = pomodoroDuration
    }

    func setPomodoroDuration(minutes: Int) {
        guard [25, 30, 45].contains(minutes) else { return }
        pomodoroTimer?.invalidate()
        pomodoroTimer = nil
        pomodoroEndDate = nil
        pomodoroRunning = false
        pomodoroDuration = TimeInterval(minutes * 60)
        pomodoroRemaining = pomodoroDuration
        UserDefaults.standard.set(minutes, forKey: "focus.durationMinutes")
    }

    func enqueue(_ event: HookySystemEvent) {
        let now = Date()
        recentEvents = recentEvents.filter { now.timeIntervalSince($0.value) < 60 }
        if currentEvent?.deduplicationKey == event.deduplicationKey { return }
        if eventQueue.contains(where: { $0.deduplicationKey == event.deduplicationKey }) { return }
        if let last = recentEvents[event.deduplicationKey], now.timeIntervalSince(last) < 10 { return }
        recentEvents[event.deduplicationKey] = now
        if eventQueue.count >= 5 { eventQueue.removeFirst() }
        eventQueue.append(event)
        presentNextEventIfNeeded()
    }

    func presentNextEventIfNeeded() {
        guard currentEvent == nil, !eventQueue.isEmpty else { return }
        let event = eventQueue.removeFirst()
        withAnimation(HookyMotion.expandFromCompact) { currentEvent = event }
        let dismissal = DispatchWorkItem { [weak self] in
            guard let self else { return }
            withAnimation(HookyMotion.collapseToIdle) { self.currentEvent = nil }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) { [weak self] in self?.presentNextEventIfNeeded() }
        }
        eventDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: dismissal)
    }

}
