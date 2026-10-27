import Foundation

/// Time the charger was cut while the Mac was plugged in, so it ran from the battery (battery-hold.json), sampled on the
/// app's existing 20 s refresh. This Mac can only pause charging by cutting the charger, so this is the real cost of a limit.
public struct BatteryHold: Codable, Equatable {
    /// "yyyy-MM-dd" → seconds.
    public var days: [String: Double] = [:]
    public init() {}

    public static let keepDays = 7
    /// A longer gap between samples means the Mac slept or the app was closed; don't count it.
    public static let maxStep: TimeInterval = 90

    static func dayKey(_ date: Date, calendar cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Adds `elapsed` seconds when the charger is cut while plugged in. Returns whether anything changed.
    @discardableResult
    public mutating func record(held: Bool, elapsed: TimeInterval, at date: Date, calendar cal: Calendar = .current) -> Bool {
        guard held, elapsed > 0, elapsed <= Self.maxStep else { return false }
        days[Self.dayKey(date, calendar: cal), default: 0] += elapsed
        prune(now: date, calendar: cal)
        return true
    }

    mutating func prune(now: Date, calendar cal: Calendar) {
        let keep = Set((0..<Self.keepDays).compactMap { cal.date(byAdding: .day, value: -$0, to: now) }.map { Self.dayKey($0, calendar: cal) })
        days = days.filter { keep.contains($0.key) }
    }

    /// The last `keepDays` days, oldest first, with zero for days without a sample.
    public func week(now: Date = Date(), calendar cal: Calendar = .current) -> [(day: Date, hours: Double)] {
        (0..<Self.keepDays).reversed().compactMap { back in
            cal.date(byAdding: .day, value: -back, to: now).map { d in (day: d, hours: (days[Self.dayKey(d, calendar: cal)] ?? 0) / 3600) }
        }
    }

    public func totalHours(now: Date = Date(), calendar cal: Calendar = .current) -> Double {
        week(now: now, calendar: cal).reduce(0) { $0 + $1.hours }
    }

    public var isEmpty: Bool { days.isEmpty }
}
