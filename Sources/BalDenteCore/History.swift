import Foundation

/// One row of the daily battery log (`daily-log.csv`).
public struct HistoryPoint: Equatable {
    public var date: Date
    public var health: Int?
    public var cycles: Int?
    public var battery: Int?
}

public enum HealthHistory {
    /// Parses `date,health_percent,cycles,battery_percent`. Bad rows are skipped, a health of 0 (older versions wrote 0 for
    /// "unknown") counts as unknown, and the result is sorted by date.
    public static func parse(_ csv: String) -> [HistoryPoint] {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let rows: [(Int, HistoryPoint)] = csv.split(whereSeparator: \.isNewline).enumerated().compactMap { n, line -> (Int, HistoryPoint)? in
            let c = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            guard c.count >= 4, let d = f.date(from: c[0]) else { return nil }
            return (n, HistoryPoint(date: d, health: Int(c[1]).flatMap { (1...150).contains($0) ? $0 : nil },   // a new battery can read a little over 100%
                                    cycles: Int(c[2]).flatMap { $0 >= 0 ? $0 : nil }, battery: Int(c[3]).flatMap { (0...100).contains($0) ? $0 : nil }))
        }
        // Sort by date, then file order, so "the latest reading of a day wins" doesn't depend on sort stability.
        return rows.sorted { ($0.1.date, $0.0) < ($1.1.date, $1.0) }.map(\.1).reduce(into: [HistoryPoint]()) { out, p in
            // One point per day: the log can hold repeats (several launches, test bundles), and the latest reading wins.
            if let l = out.last, l.date == p.date { out[out.count - 1] = p } else { out.append(p) }
        }
    }

    /// Health and cycle change measured between each series' own first and last readings, so a missing health value on
    /// the first or last day doesn't stretch the time span or misstate the change.
    public struct Summary: Equatable {
        public var healthNow: Int?
        public var healthDelta: Int?
        public var healthDays: Int?
        public var cyclesAdded: Int?
        /// Days until health reaches `projectionTarget` at the logged pace; nil without a steady decline.
        public var daysToTarget: Int?
    }

    public static let projectionTarget = 80

    /// Least-squares line through the health points. Needs 3+ points over 14+ days and a falling trend, and ignores
    /// projections beyond 10 years, which would be noise rather than a forecast.
    public static func daysToReach(_ target: Int, _ h: [(Date, Int)]) -> Int? {
        guard h.count >= 3, let first = h.first, let last = h.last, let cur = h.last?.1 else { return nil }
        let xs = h.map { $0.0.timeIntervalSince(first.0) / 86400 }, ys = h.map { Double($0.1) }
        guard last.0.timeIntervalSince(first.0) >= 14 * 86400 else { return nil }
        if cur <= target { return 0 }
        let n = Double(h.count), mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard den > 0 else { return nil }
        let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / den
        guard slope < -0.001 else { return nil }
        let days = (Double(target) - ys[ys.count - 1]) / slope
        return days <= 3650 ? Int(days.rounded(.up)) : nil
    }

    public static func summary(_ pts: [HistoryPoint], calendar: Calendar = .current) -> Summary {
        let h = pts.compactMap { p in p.health.map { (p.date, $0) } }
        let c = pts.compactMap(\.cycles)
        var s = Summary(healthNow: h.last?.1)
        if h.count > 1, let a = h.first, let b = h.last {
            s.healthDelta = b.1 - a.1
            s.healthDays = max(1, calendar.dateComponents([.day], from: a.0, to: b.0).day ?? 1)
        }
        s.daysToTarget = daysToReach(projectionTarget, h)
        if c.count > 1 { s.cyclesAdded = max(0, c.last! - c.first!) }
        return s
    }

    /// At most `max` points, always keeping the first and last, so years of rows draw as fast as a few weeks.
    public static func downsample(_ pts: [HistoryPoint], max: Int) -> [HistoryPoint] {
        guard max >= 2, pts.count > max else { return pts }
        return (0..<max).map { pts[$0 * (pts.count - 1) / (max - 1)] }
    }
}

/// Turns a calendar event into a "Ready by" slot.
public enum ReadyPlan {
    /// The first event that still leaves time to charge: its start minus the buffer must be at least `margin` minutes away.
    public static func pick(starts: [Date], now: Date, bufferMinutes: Int, margin: Int = 10) -> Date? {
        starts.sorted().first { $0.addingTimeInterval(TimeInterval(-bufferMinutes * 60)) > now.addingTimeInterval(TimeInterval(margin * 60)) }
    }

    /// Timed events worth showing, soonest first, each marked with whether there is still time to charge for it.
    public static func upcoming(starts: [Date], now: Date, bufferMinutes: Int, margin: Int = 10, limit: Int = 4) -> [(start: Date, chargeable: Bool)] {
        starts.filter { $0 > now }.sorted().prefix(limit).map { s in
            (s, s.addingTimeInterval(TimeInterval(-bufferMinutes * 60)) > now.addingTimeInterval(TimeInterval(margin * 60)))
        }
    }

    /// The daemon's `ready on` spec (`weekday@HH:MM@percent`) for being ready `bufferMinutes` before `start`.
    public static func spec(eventStart start: Date, bufferMinutes: Int, percent: Int = 100, calendar cal: Calendar = .current) -> String {
        let ready = start.addingTimeInterval(TimeInterval(-bufferMinutes * 60))
        let c = cal.dateComponents([.weekday, .hour, .minute], from: ready)
        return "\(c.weekday ?? 2)@" + String(format: "%02d:%02d", c.hour ?? 7, c.minute ?? 30) + "@\(percent)"
    }
}
