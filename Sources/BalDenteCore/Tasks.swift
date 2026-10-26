import Foundation

/// A repeating job for the helper to run: top up, calibrate, discharge, or switch Low Power Mode.
/// The limit itself is not an action: zones own it, so a scheduled limit would just be overwritten at the next zone refresh.
public struct ScheduledTask: Codable, Equatable, Identifiable {
    public enum Action: String, Codable, CaseIterable {
        case topUp, calibrate, discharge, lowPowerOn, lowPowerOff
        public var title: String {
            switch self {
            case .topUp: "Top Up to 100%"
            case .calibrate: "Calibrate"
            case .discharge: "Discharge"
            case .lowPowerOn: "Low Power Mode on"
            case .lowPowerOff: "Low Power Mode off"
            }
        }
    }
    public enum Repeat: String, Codable, CaseIterable {
        case once, daily, weekdays, weekly, biweekly, monthly, yearly
        public var title: String {
            switch self {
            case .once: "Don't repeat"
            case .daily: "Daily"
            case .weekdays: "Weekdays"
            case .weekly: "Weekly"
            case .biweekly: "Every two weeks"
            case .monthly: "Monthly"
            case .yearly: "Yearly"
            }
        }
    }

    public static let maxCount = 20
    /// How late a task may start without "catch up": the helper checks every 20 s, so a few minutes covers a busy moment.
    public static let onTimeWindow: TimeInterval = 10 * 60
    /// With catch-up, a missed run still happens if the Mac wakes within this long.
    public static let catchUpWindow: TimeInterval = 24 * 3600

    public var id: String
    public var action: Action
    /// Discharge target, 20 to 90. Ignored by other actions.
    public var percent: Int
    public var repeats: Repeat
    public var hour: Int
    public var minute: Int
    /// The first day it applies. Weekly, biweekly, monthly and yearly repeats take their weekday, day or date from it.
    public var anchor: Date
    public var enabled: Bool
    public var catchUp: Bool
    public var lastRun: Date?

    public init(id: String = ScheduledTask.newID(), action: Action, percent: Int = 50, repeats: Repeat, hour: Int, minute: Int,
                anchor: Date, enabled: Bool = true, catchUp: Bool = true, lastRun: Date? = nil) {
        self.id = id; self.action = action; self.percent = percent; self.repeats = repeats; self.hour = hour; self.minute = minute
        self.anchor = anchor; self.enabled = enabled; self.catchUp = catchUp; self.lastRun = lastRun
    }

    public static func newID() -> String { String(UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12)) }
    public static func validID(_ s: String) -> Bool {
        (1...16).contains(s.count) && s.allSatisfy { $0.isLetter && $0.isASCII || $0.isNumber && $0.isASCII }
    }

    // MARK: Schedule math

    private static func daysInMonth(_ d: Date, _ cal: Calendar) -> Int { cal.range(of: .day, in: .month, for: d)?.count ?? 31 }

    /// When this task fires on the calendar day containing `day`, or nil if it does not apply that day.
    /// A monthly or yearly date past the end of a short month fires on the month's last day instead of being skipped.
    public func occurrence(on day: Date, calendar cal: Calendar = .current) -> Date? {
        let start = cal.startOfDay(for: day), anchorDay = cal.startOfDay(for: anchor)
        guard start >= anchorDay else { return nil }
        let a = cal.dateComponents([.month, .day, .weekday], from: anchor), d = cal.dateComponents([.month, .day, .weekday], from: day)
        let applies: Bool
        switch repeats {
        case .once: applies = start == anchorDay
        case .daily: applies = true
        case .weekdays: applies = (2...6).contains(d.weekday ?? 0)
        case .weekly: applies = d.weekday == a.weekday
        case .biweekly:
            let days = cal.dateComponents([.day], from: anchorDay, to: start).day ?? 0
            applies = d.weekday == a.weekday && (days / 7) % 2 == 0
        case .monthly: applies = d.day == min(a.day ?? 1, Self.daysInMonth(day, cal))
        case .yearly: applies = d.month == a.month && d.day == min(a.day ?? 1, Self.daysInMonth(day, cal))
        }
        guard applies else { return nil }
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// The next firing strictly after `now`, looking up to a year and a bit ahead.
    public func nextRun(after now: Date, calendar cal: Calendar = .current) -> Date? {
        guard enabled else { return nil }
        for off in 0...400 {
            guard let day = cal.date(byAdding: .day, value: off, to: now), let o = occurrence(on: day, calendar: cal) else { continue }
            if o > now { return o }
        }
        return nil
    }

    /// The firing the helper should run now, if any: the latest one that has passed, is inside the window and has not run yet.
    public func due(at now: Date, calendar cal: Calendar = .current) -> Date? {
        guard enabled else { return nil }
        let window = catchUp ? Self.catchUpWindow : Self.onTimeWindow
        var best: Date?
        for off in 0...2 {
            guard let day = cal.date(byAdding: .day, value: -off, to: now), let o = occurrence(on: day, calendar: cal) else { continue }
            guard o <= now, now.timeIntervalSince(o) <= window, o > (lastRun ?? .distantPast) else { continue }
            if best == nil || o > best! { best = o }
        }
        return best
    }

    // MARK: Wire format (one command per task; no JSON from the socket)

    /// `task add <id> <action> <percent> <repeat> <hour> <minute> <anchor epoch> <catchUp 0|1> <enabled 0|1>`
    public var wire: String {
        "task add \(id) \(action.rawValue) \(percent) \(repeats.rawValue) \(hour) \(minute) \(Int(anchor.timeIntervalSince1970)) \(catchUp ? 1 : 0) \(enabled ? 1 : 0)"
    }

    /// Parses the tokens after `task add`. Returns nil for anything out of range, so a bad client can't store nonsense.
    public static func parse(_ t: [String]) -> ScheduledTask? {
        guard t.count == 9, validID(t[0]), let action = Action(rawValue: t[1]), let pct = Int(t[2]), (20...90).contains(pct),
              let rep = Repeat(rawValue: t[3]), let h = Int(t[4]), (0..<24).contains(h), let m = Int(t[5]), (0..<60).contains(m),
              let epoch = Double(t[6]), epoch > 946_684_800, epoch < 4_102_444_800,   // years 2000 to 2100
              ["0", "1"].contains(t[7]), ["0", "1"].contains(t[8]) else { return nil }
        return ScheduledTask(id: t[0], action: action, percent: pct, repeats: rep, hour: h, minute: m,
                             anchor: Date(timeIntervalSince1970: epoch), enabled: t[8] == "1", catchUp: t[7] == "1")
    }

    public var summary: String {
        let what = action == .discharge ? "Discharge to \(percent)%" : action.title
        let time = String(format: "%02d:%02d", hour, minute)
        return "\(what) · \(repeats.title) · \(time)"
    }
}

/// One line of the task history the helper keeps.
public struct TaskRun: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var date: Date
    public var taskID: String
    public var action: ScheduledTask.Action
    /// "Started", or why it did not.
    public var note: String
    public static let maxKept = 50
    public init(date: Date, taskID: String, action: ScheduledTask.Action, note: String) {
        self.date = date; self.taskID = taskID; self.action = action; self.note = note
    }
}

public enum TaskBook {
    /// Adds or replaces by id (a replaced task keeps its last run), capped at `maxCount`. A task never seen before starts with
    /// `lastRun = now`, so only future firings run and creating "daily 07:00" at 09:00 does not fire at once with catch-up on.
    public static func upsert(_ list: [ScheduledTask], _ t: ScheduledTask, now: Date) -> [ScheduledTask] {
        var out = list
        var t = t
        if let i = out.firstIndex(where: { $0.id == t.id }) { t.lastRun = out[i].lastRun; out[i] = t }
        else if out.count < ScheduledTask.maxCount { t.lastRun = now; out.append(t) }
        return out
    }
}
