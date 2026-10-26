import Foundation

/// One moment the user probably left: the charger was unplugged, or (with no unplug that day) a zone was left.
/// The local weekday and wall-clock minute are stored as they were when it happened, so a later DST switch or a trip
/// to another time zone doesn't shift old samples: "8:10 on a Monday" stays 8:10.
public struct HabitEvent: Codable, Equatable {
    public enum Kind: String, Codable { case unplug, zoneExit }
    public var date: Date
    public var kind: Kind
    /// Local day the event belongs to (yyyy-MM-dd). The day starts at `HabitPlanner.dayStartHour`, so a 1 AM unplug counts
    /// toward the evening before rather than becoming that day's "first departure".
    public var day: String
    /// 1 = Sunday ... 7 = Saturday, of `day`.
    public var weekday: Int
    /// Minutes after local midnight when it happened (can exceed 1440 for events after midnight but before the day start).
    public var minute: Int

    public init(date: Date, kind: Kind, calendar cal: Calendar = .current) {
        self.date = date; self.kind = kind
        let shifted = date.addingTimeInterval(TimeInterval(-HabitPlanner.dayStartHour * 3600))
        let c = cal.dateComponents([.year, .month, .day, .weekday], from: shifted)
        day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        weekday = c.weekday ?? 1
        let t = cal.dateComponents([.hour, .minute], from: date)
        let m = (t.hour ?? 0) * 60 + (t.minute ?? 0)
        minute = m < HabitPlanner.dayStartHour * 60 ? m + 1440 : m
    }
}

/// The on-device rolling record of departures. Compact: one small struct per event, at most `maxWeeks` weeks old.
public struct HabitLog: Codable, Equatable {
    public var events: [HabitEvent] = []
    public init(events: [HabitEvent] = []) { self.events = events }

    public static let maxWeeks = 8
    /// An unplug followed by a plug within this many minutes was just moving the cable, not leaving.
    public static let replugMinutes = 10.0
    static let maxEvents = 500

    public mutating func record(_ e: HabitEvent, now: Date = Date()) {
        events.append(e)
        prune(now: now)
    }

    /// The charger came back: drop an unplug from moments ago.
    public mutating func plugged(at d: Date) {
        if let last = events.last, last.kind == .unplug, d.timeIntervalSince(last.date) >= 0,
           d.timeIntervalSince(last.date) < Self.replugMinutes * 60 { events.removeLast() }
    }

    public mutating func prune(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Double(Self.maxWeeks) * 7 * 86400)
        events = Array(events.filter { $0.date >= cutoff && $0.date <= now.addingTimeInterval(3600) }.suffix(Self.maxEvents))
    }
}

/// A suggested Ready by plan: the weekdays that share a consistent departure, and the time to be full by.
public struct HabitSuggestion: Equatable {
    /// Weekdays (1 = Sunday ... 7 = Saturday) with the typical departure minute for each.
    public var departures: [Int: Int]
    /// When to be full, per weekday: a little before the typical departure, on a 5-minute boundary.
    public var readyBy: [Int: Int]
    public var percent = 100

    public init(departures: [Int: Int], readyBy: [Int: Int], percent: Int = 100) {
        self.departures = departures; self.readyBy = readyBy; self.percent = percent
    }

    public var slots: [Slot] {
        readyBy.keys.sorted().map { Slot(weekday: $0, hour: readyBy[$0]! / 60, minute: readyBy[$0]! % 60, percent: percent) }
    }

    /// Identifies this suggestion so "Not now" can skip exactly it and notifications fire once.
    public var signature: String { slots.map { "\($0.weekday)@\($0.hour):\($0.minute)" }.joined(separator: ",") }

    /// Same weekdays and every time within 20 minutes: the pattern drifting by a few minutes as data comes in is still
    /// "this" suggestion, so "Don't suggest this again" keeps holding.
    public func isSimilar(to o: HabitSuggestion) -> Bool {
        Set(readyBy.keys) == Set(o.readyBy.keys) && readyBy.allSatisfy { abs($0.value - (o.readyBy[$0.key] ?? .min / 2)) <= 20 }
    }

    /// "You usually unplug around 8:10 on weekdays. Charge to 100% by 8:00?"
    public var question: String {
        "You usually unplug around \(HabitPlanner.describe(departures)). Charge to \(percent)% by \(HabitPlanner.describe(readyBy))?"
    }
}

/// Finds a confident daily departure pattern in a `HabitLog`. UI-free and deterministic, so it's unit-tested.
public enum HabitPlanner {
    public static let dayStartHour = 4
    /// Each weekday needs this many observed days...
    public static let minSamples = 3
    /// ...this share of them inside one cluster...
    public static let consistency = 0.6
    /// ...where a cluster is everything within this many minutes of the median.
    public static let clusterMinutes = 45
    /// And nothing is suggested until the log spans this many days, so the first weeks never produce a guess.
    public static let minSpanDays = 14
    /// How long before the typical departure to be full.
    public static let leadMinutes = 10

    /// The first departure of each day: its earliest unplug, or the earliest zone exit if there was no unplug.
    public static func firstDepartures(_ log: HabitLog) -> [HabitEvent] {
        Dictionary(grouping: log.events, by: \.day).values.compactMap { day in
            let unplugs = day.filter { $0.kind == .unplug }
            return (unplugs.isEmpty ? day : unplugs).min { $0.minute < $1.minute }
        }.sorted { $0.date < $1.date }
    }

    /// Typical departure minute for a set of samples, or nil when they aren't consistent enough.
    public static func typicalMinute(_ minutes: [Int]) -> Int? {
        guard minutes.count >= minSamples else { return nil }
        let med = median(minutes)
        let inliers = minutes.filter { abs($0 - med) <= clusterMinutes }
        guard inliers.count >= minSamples, Double(inliers.count) / Double(minutes.count) >= consistency else { return nil }
        return median(inliers)
    }

    public static func suggest(_ log: HabitLog, now: Date = Date()) -> HabitSuggestion? {
        guard let first = log.events.map(\.date).min(), now.timeIntervalSince(first) >= Double(minSpanDays) * 86400 else { return nil }
        let byWeekday = Dictionary(grouping: firstDepartures(log), by: \.weekday)
        var departures: [Int: Int] = [:], ready: [Int: Int] = [:]
        for (wd, evs) in byWeekday {
            guard let m = typicalMinute(evs.map(\.minute)), m < 1440 else { continue }   // after-midnight departures can't be a slot
            let r = max(0, (m - leadMinutes) / 5 * 5)
            departures[wd] = m; ready[wd] = r
        }
        return departures.isEmpty ? nil : HabitSuggestion(departures: departures, readyBy: ready)
    }

    /// Whether the current schedule already has the battery full by each suggested time. A slot much earlier doesn't count:
    /// the helper holds 100% only until 30 minutes after a slot, so it must be at most 20 minutes before the suggested time.
    public static func isCovered(_ s: HabitSuggestion, by cs: ChargeSchedule) -> Bool {
        guard cs.enabled else { return false }
        return s.slots.allSatisfy { want in
            cs.slots.contains { $0.weekday == want.weekday && $0.percent >= want.percent && $0.hour * 60 + $0.minute <= want.hour * 60 + want.minute
                && $0.hour * 60 + $0.minute >= want.hour * 60 + want.minute - 20 }
        }
    }

    /// The suggestion's slots plus any existing (enabled) slots on other weekdays, so accepting doesn't wipe a day the user set by hand.
    public static func merged(_ s: HabitSuggestion, into cs: ChargeSchedule) -> [Slot] {
        let mine = Set(s.readyBy.keys)
        let keep = cs.enabled ? cs.slots.filter { !mine.contains($0.weekday) } : []
        return (keep + s.slots).sorted { ($0.weekday, $0.hour, $0.minute) < ($1.weekday, $1.hour, $1.minute) }
    }

    /// "8:10 on weekdays", "8:10 on Mon, Wed · 9:30 on Sat": days sharing a time are grouped.
    public static func describe(_ times: [Int: Int], calendar cal: Calendar = .current) -> String {
        let byTime = Dictionary(grouping: times.keys) { times[$0]! / 5 * 5 }
        return byTime.keys.sorted().map { t in "\(clock(t)) on \(dayList(byTime[t]!, calendar: cal))" }.joined(separator: " · ")
    }

    public static func dayList(_ days: [Int], calendar cal: Calendar = .current) -> String {
        let set = Set(days)
        if set == Set(1...7) { return "every day" }
        if set == Set(2...6) { return "weekdays" }
        if set == [1, 7] { return "weekends" }
        let order = [2, 3, 4, 5, 6, 7, 1]
        return order.filter(set.contains).map { cal.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
    }

    public static func clock(_ minute: Int) -> String { String(format: "%d:%02d", (minute / 60) % 24, minute % 60) }

    static func median(_ xs: [Int]) -> Int {
        let s = xs.sorted(); let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}

extension ChargeSchedule {
    /// The daemon's `ready on` argument: `weekday@HH:MM@percent,...`.
    public static func spec(_ slots: [Slot]) -> String {
        slots.map { "\($0.weekday)@" + String(format: "%02d:%02d", $0.hour, $0.minute) + "@\($0.percent)" }.joined(separator: ",")
    }
}
