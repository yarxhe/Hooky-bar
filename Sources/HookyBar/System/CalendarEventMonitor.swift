import AppKit
import EventKit

final class CalendarEventAdapter: SystemEventAdapter {
    let kind: HookySystemEvent.Kind = .calendar
    let capability = IntegrationCapabilityDeclaration(
        id: "system.calendar",
        permissions: [.calendar]
    )

    private let eventStore = EKEventStore()
    private var receive: ((HookySystemEvent) -> Void)?
    private var timer: Timer?
    private var lastEventID: String?

    func start(receive: @escaping (HookySystemEvent) -> Void) {
        self.receive = receive
        let authorization = EKEventStore.authorizationStatus(for: .event)
        if authorization == .fullAccess {
            startMonitoring()
            return
        }
        guard authorization == .notDetermined else { return }
        eventStore.requestFullAccessToEvents { [weak self] granted, _ in
            DispatchQueue.main.async {
                guard granted else { return }
                self?.startMonitoring()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        receive = nil
        lastEventID = nil
    }

    private func startMonitoring() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    private func refresh() {
        let now = Date()
        let end = now.addingTimeInterval(24 * 60 * 60)
        let predicate = eventStore.predicateForEvents(withStart: now, end: end, calendars: nil)
        guard let event = eventStore.events(matching: predicate)
            .filter({ !$0.isAllDay && $0.endDate > now })
            .sorted(by: { $0.startDate < $1.startDate })
            .first else { return }
        let seconds = event.startDate.timeIntervalSince(now)
        guard seconds > 0, seconds <= 10 * 60, lastEventID != event.eventIdentifier else { return }
        lastEventID = event.eventIdentifier
        receive?(HookySystemEvent(
            kind: .calendar,
            title: event.title ?? L10n.tr("event.calendar.meeting"),
            subtitle: L10n.tr("event.calendar.inMinutes.format", max(1, Int(ceil(seconds / 60)))),
            symbol: "calendar.badge.clock",
            tint: .systemRed,
            deduplicationKey: "calendar-\(event.eventIdentifier ?? event.title ?? "event")"
        ))
    }
}
