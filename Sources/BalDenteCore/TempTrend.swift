import Foundation

/// Recent battery temperatures from the 20 s refresh, for the Overview's cooling-down card. In memory only; UI-free so it is tested.
public struct TempTrend: Equatable {
    public struct Sample: Equatable { public var date: Date; public var celsius: Double }
    public private(set) var samples: [Sample] = []
    /// How much history the card draws, and how much the rate looks at.
    public static let keep: TimeInterval = 30 * 60
    public static let rateWindow: TimeInterval = 10 * 60

    public init() {}

    public mutating func add(_ celsius: Double, at date: Date = Date()) {
        samples.removeAll { date.timeIntervalSince($0.date) > Self.keep || $0.date > date }
        samples.append(Sample(date: date, celsius: celsius))
    }

    public var latest: Double? { samples.last?.celsius }

    /// °C per minute over the last 10 minutes (least squares), or nil with under 3 samples or under 2 minutes of data.
    public func ratePerMinute() -> Double? {
        guard let end = samples.last?.date else { return nil }
        let recent = samples.filter { end.timeIntervalSince($0.date) <= Self.rateWindow }
        guard recent.count >= 3, let first = recent.first, end.timeIntervalSince(first.date) >= 120 else { return nil }
        let xs = recent.map { $0.date.timeIntervalSince(first.date) / 60 }, ys = recent.map(\.celsius)
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        let den = zip(xs, xs).map { ($0 - mx) * ($1 - mx) }.reduce(0, +)
        guard den > 0 else { return nil }
        return zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +) / den
    }

    /// Minutes until it cools to `target` at the current rate; nil unless it is above target and falling.
    public func minutesUntil(_ target: Double) -> Int? {
        guard let t = latest, t > target, let r = ratePerMinute(), r < -0.01 else { return nil }
        return max(1, Int(((t - target) / -r).rounded(.up)))
    }

    /// "38.1 °C, falling 0.4 °C every 10 min. Charging resumes at 37 °C in about 3 min."
    public func summary(resumeAt target: Int) -> String {
        guard let t = latest else { return "Waiting for a temperature reading." }
        let now = String(format: "%.1f °C", t)
        guard let r = ratePerMinute() else { return "\(now). Charging resumes at \(target) °C." }
        let per10 = abs(r * 10)
        let move = per10 < 0.1 ? "holding steady" : String(format: "%@ %.1f °C every 10 min", r < 0 ? "falling" : "rising", per10)
        let eta = minutesUntil(Double(target)).map { " in about \($0) min" } ?? ""
        return "\(now), \(move). Charging resumes at \(target) °C\(eta)."
    }
}
