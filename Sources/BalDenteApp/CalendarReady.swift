import BalDenteCore
import EventKit
import SwiftUI

/// Sets "Ready by" from your calendar: be at 100% a chosen number of minutes before the next timed event.
/// Event-driven: it recomputes when the calendar database changes (EKEventStoreChanged) and when the model asks
/// (at most every 30 minutes, from the refresh that already runs). It never polls the calendar on its own.
@MainActor
final class CalendarReady: ObservableObject {
    @Published var enabled = UserDefaults.standard.bool(forKey: "calendarReady") {
        didSet { UserDefaults.standard.set(enabled, forKey: "calendarReady"); enabled ? start() : stop() }
    }
    @Published var buffer = max(10, UserDefaults.standard.integer(forKey: "calendarBuffer") == 0 ? 30 : UserDefaults.standard.integer(forKey: "calendarBuffer")) {
        didSet { UserDefaults.standard.set(buffer, forKey: "calendarBuffer"); recompute() }
    }
    struct Upcoming: Identifiable { let id: String; let title: String; let start: Date; let calendar: String; let chargeable: Bool; let isTarget: Bool }
    @Published private(set) var next: (title: String, start: Date)?
    /// The next few timed events, so the card can show what BalDente is (and isn't) planning around.
    @Published private(set) var upcoming: [Upcoming] = []
    /// The helper was unreachable when we last tried to send the schedule; retry once it answers.
    private var needsSync = false
    @Published private(set) var denied = false
    weak var model: Model?
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var lastRun = Date.distantPast

    /// What we last sent the helper, remembered across launches so a relaunch doesn't reset its "already ran" list.
    private var lastSpec: String? {
        get { UserDefaults.standard.string(forKey: "calendarLastSpec") }
        set { UserDefaults.standard.set(newValue, forKey: "calendarLastSpec") }
    }

    func resumeIfEnabled() { if enabled { start() } }

    private func start() {
        Task {
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            guard granted else { denied = true; enabled = false; return }
            denied = false
            if observer == nil {
                observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.recompute() }
                }
            }
            recompute()
        }
    }

    private func stop() {
        if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
        next = nil; upcoming = []; needsSync = false
        if lastSpec != nil { lastSpec = nil; model?.cmd("ready off") }
    }

    /// Called from the model's regular refresh; cheap unless 30 minutes have passed.
    /// Also runs as soon as the planned event has started (so the next one is picked up) or the helper has come back.
    func tick() {
        guard enabled else { return }
        let started = next.map { $0.start <= Date() } ?? false
        if started || (needsSync && model?.status != nil) || Date().timeIntervalSince(lastRun) > 1800 { recompute() }
    }

    func recompute() {
        guard enabled else { return }
        lastRun = Date()
        let now = Date()
        let events = store.events(matching: store.predicateForEvents(withStart: now, end: now.addingTimeInterval(36 * 3600), calendars: nil))
            .filter { e in
                !e.isAllDay && e.status != .canceled && e.calendar.type != .birthday
                    && !(e.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false)
            }
        let rows = ReadyPlan.upcoming(starts: events.map(\.startDate), now: now, bufferMinutes: buffer)
        let target = ReadyPlan.pick(starts: events.map(\.startDate), now: now, bufferMinutes: buffer)
        upcoming = rows.compactMap { r in
            guard let e = events.first(where: { $0.startDate == r.start }) else { return nil }
            return Upcoming(id: "\(e.eventIdentifier ?? e.title ?? "")\(r.start.timeIntervalSince1970)", title: e.title ?? "Event", start: r.start,
                            calendar: e.calendar.title, chargeable: r.chargeable, isTarget: r.start == target)
        }
        guard let start = target, let event = events.first(where: { $0.startDate == start }) else {
            next = nil
            // The helper's slot repeats weekly, so clear ours once its event has passed.
            if lastSpec != nil {
                if model?.status != nil { lastSpec = nil; needsSync = false; model?.cmd("ready off") } else { needsSync = true }
            }
            return
        }
        next = (event.title ?? "Event", start)
        let spec = ReadyPlan.spec(eventStart: start, bufferMinutes: buffer)
        // Only remember a spec the helper actually received; otherwise a helper that was offline would never get it.
        guard model?.status != nil else { needsSync = true; return }
        needsSync = false
        if spec != lastSpec { lastSpec = spec; model?.cmd("ready zone any"); model?.cmd("ready travel 0"); model?.cmd("ready on \(spec)") }
    }
}

struct CalendarCard: View {
    @ObservedObject var model: Model
    @ObservedObject var cal: CalendarReady

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Calendar Ready by", systemImage: "calendar.badge.clock").font(.system(size: 16, weight: .bold, design: .rounded))
            Toggle("Be full before my next event", isOn: $cal.enabled).toggleStyle(.switch).disabled(model.status == nil)
            Stepper("\(cal.buffer) min before it starts", value: $cal.buffer, in: 10...180, step: 5).disabled(!cal.enabled)
            if cal.enabled {
                if cal.upcoming.isEmpty {
                    Label("No timed events in the next 36 hours, so nothing is scheduled.", systemImage: "moon.zzz").font(.caption).foregroundStyle(.secondary)
                } else {
                    if let n = cal.next {
                        let full = n.start.addingTimeInterval(-Double(cal.buffer) * 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Full by \(full.formatted(date: .omitted, time: .shortened)) for \(n.title)").font(.callout.weight(.semibold))
                            Text("Starts \(n.start.formatted(.relative(presentation: .named))) · charging begins about \(full.addingTimeInterval(-ChargeSchedule.leadMinutes(percent: model.percent) * 60).formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(cal.upcoming) { e in
                            HStack(spacing: 8) {
                                Image(systemName: e.isTarget ? "bolt.circle.fill" : (e.chargeable ? "circle" : "clock.badge.exclamationmark"))
                                    .foregroundStyle(e.isTarget ? Color.teal : (e.chargeable ? Color.secondary : Color.orange))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(e.title).font(.caption.weight(.medium)).lineLimit(1)
                                    Text("\(e.start.formatted(date: .abbreviated, time: .shortened)) · \(e.calendar)\(e.chargeable || e.isTarget ? "" : " · too soon to charge for")")
                                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }
            if cal.denied {
                Text("Calendar access was denied. Allow it in System Settings > Privacy & Security > Calendars.").font(.caption).foregroundStyle(.orange)
            }
            Text("While on, your calendar owns the Ready by schedule. Only timed, accepted events count.").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(18).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .glassEffect(.regular.tint(.teal.opacity(0.14)), in: .rect(cornerRadius: 26))
        .settingAnchor("Calendar Ready by")
    }
}
