import Foundation

/// Time spent above 80% in each zone over the last week (zone-wear.json), sampled on the app's existing 20 s refresh.
/// Feeds the History card and the "lower this zone's limit?" suggestion. Suggest only; lowering is always the user's tap.
public struct ZoneWear: Codable, Equatable {
    /// "yyyy-MM-dd" → zone label → seconds above `threshold`.
    public var days: [String: [String: Double]] = [:]
    public init() {}

    public static let threshold = 80
    public static let keepDays = 7
    /// A longer gap between samples means the Mac slept or the app was closed; don't count it.
    public static let maxStep: TimeInterval = 90

    static func dayKey(_ date: Date, calendar cal: Calendar) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Adds `elapsed` seconds to `zone` when the charge is above the threshold. Top Up and Travel Mode are the user's choice, so they don't count.
    /// Returns whether anything changed.
    @discardableResult
    public mutating func record(zone: String, percent: Int, elapsed: TimeInterval, at date: Date, calendar cal: Calendar = .current) -> Bool {
        guard elapsed > 0, elapsed <= Self.maxStep, percent > Self.threshold, !ChangeEvent.manualLabels.contains(zone) else { return false }
        let key = Self.dayKey(date, calendar: cal)
        days[key, default: [:]][zone, default: 0] += elapsed
        prune(now: date, calendar: cal)
        return true
    }

    mutating func prune(now: Date, calendar cal: Calendar) {
        let keep = Set((0..<Self.keepDays).compactMap { cal.date(byAdding: .day, value: -$0, to: now) }.map { Self.dayKey($0, calendar: cal) })
        days = days.filter { keep.contains($0.key) }
    }

    /// Hours above the threshold per zone over the last `keepDays` days, most first. "Default" is shown as "Everywhere else".
    public func weekly(now: Date = Date(), calendar cal: Calendar = .current) -> [(zone: String, hours: Double)] {
        var copy = self; copy.prune(now: now, calendar: cal)
        var total: [String: Double] = [:]
        for zones in copy.days.values { for (z, s) in zones { total[z, default: 0] += s / 3600 } }
        return total.map { (zone: $0.key, hours: $0.value) }.sorted { $0.hours > $1.hours }
    }

    public var recordedDays: Int { days.count }
}

/// "Your Mac spent 22 h above 80% at School this week. Lower its limit to 80%?"
public struct WearSuggestion: Equatable {
    /// The label the helper uses ("Default" for Everywhere else).
    public var zone: String
    public var hours: Int
    public var upper: Int

    public var displayName: String { ChangeEvent.zoneName(zone) }
    public static let newUpper = 80
    public static let newLower = 75

    public var text: String {
        "Your Mac spent \(hours) h above \(ZoneWear.threshold)% at \(displayName) this week. Lowering its limit from \(upper)% to \(Self.newUpper)% would slow battery wear."
    }

    /// Hours a week above 80% before it's worth mentioning.
    public static let minHours = 15.0
    /// Days of data needed first, so one long afternoon doesn't trigger it.
    public static let minDays = 3

    public static func suggest(_ wear: ZoneWear, config: Config, dismissed: Set<String> = [], now: Date = Date(), calendar cal: Calendar = .current) -> WearSuggestion? {
        guard wear.recordedDays >= minDays else { return nil }
        for (zone, hours) in wear.weekly(now: now, calendar: cal) where hours >= minHours && !dismissed.contains(zone) {
            let upper = zone == "Default" ? config.defaultUpper : config.zones.first { $0.name == zone }?.upper
            if let upper, upper > newUpper { return WearSuggestion(zone: zone, hours: Int(hours.rounded()), upper: upper) }
        }
        return nil
    }
}
