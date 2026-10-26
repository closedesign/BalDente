import Foundation

/// Calibration bookkeeping that needs no timers: the reminder rides on the once-a-day log, the history view on the daily rows.
public enum CalibrationReminder {
    public static let afterDays = 90
    public static let repeatDays = 30

    /// Whole days since `date`, never negative.
    public static func days(since date: Date, now: Date = Date()) -> Int { max(0, Int(now.timeIntervalSince(date) / 86400)) }

    /// Remind once `afterDays` have passed since the last calibration (or since BalDente first checked, if none is known),
    /// then at most every `repeatDays` until one is done.
    public static func due(last: Date?, baseline: Date, lastReminded: Date?, now: Date = Date()) -> Bool {
        let since = last ?? baseline
        guard days(since: since, now: now) >= afterDays else { return false }
        if let r = lastReminded, r > since, days(since: r, now: now) < repeatDays { return false }
        return true
    }
}

/// One completed calibration set beside the health reading before and after it.
public struct CalibrationEntry: Equatable {
    public var date: Date
    public var before: Int?
    public var after: Int?
}

public enum CalibrationHistory {
    /// `before` is the last reading from an earlier day, `after` the first reading from a later day (nil until the next daily row).
    /// Newest first.
    public static func entries(dates: [Date], points: [HistoryPoint], calendar: Calendar = .current) -> [CalibrationEntry] {
        let withHealth = points.filter { $0.health != nil }.sorted { $0.date < $1.date }
        return dates.sorted(by: >).map { d in
            let day = calendar.startOfDay(for: d)
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            return CalibrationEntry(date: d,
                                    before: withHealth.last { $0.date < day }?.health,
                                    after: withHealth.first { $0.date >= next }?.health)
        }
    }
}
