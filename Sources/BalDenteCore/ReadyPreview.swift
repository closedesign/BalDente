import Foundation

/// What the next Ready by departure will do, in words, for the "Leaving soon" card on Overview.
/// Mirrors the helper's start rule (`checkReadyBy` in baldented) so the card never promises more than the helper does.
public struct ReadyPreview: Equatable {
    public enum Outcome: Equatable {
        case willStart(at: Date)
        case startingNow
        case needsPower(by: Date)
        case blockedByZone(zone: String, active: String)
        case tooHot(tempC: Double)
        case alreadyThere
    }
    public var ready: Date
    public var percent: Int
    public var outcome: Outcome

    /// Nil when Ready by is off, a top-up is already running, or the next departure is further away than `within`.
    public static func make(_ cs: ChargeSchedule, activeLabel: String, percent: Int, plugged: Bool, tempC: Double? = nil, taskActive: Bool, now: Date,
                            within: TimeInterval = 24 * 3600, calendar: Calendar = .current) -> ReadyPreview? {
        guard !taskActive, percent >= 0, let next = cs.nextSlot(after: now, calendar: calendar),
              next.ready.timeIntervalSince(now) <= within else { return nil }
        let target = next.slot.percent
        func result(_ o: Outcome) -> ReadyPreview { ReadyPreview(ready: next.ready, percent: target, outcome: o) }
        if percent >= target { return result(.alreadyThere) }
        let start = next.ready.addingTimeInterval(-ChargeSchedule.leadMinutes(percent: percent, target: target) * 60)
        if let z = cs.onlyZone, Target.wire(z) != Target.wire(activeLabel) {
            return result(.blockedByZone(zone: z, active: activeLabel))
        }
        if !plugged { return result(.needsPower(by: start)) }
        if let t = tempC, t >= Double(HeatLimit.ratedChargeMax) { return result(.tooHot(tempC: t)) }
        return result(now >= start ? .startingNow : .willStart(at: start))
    }

    /// True when the card should look like a warning rather than reassurance.
    public var needsAttention: Bool {
        switch outcome {
        case .blockedByZone, .needsPower, .tooHot: true
        default: false
        }
    }

    private static func time(_ d: Date) -> String { d.formatted(date: .omitted, time: .shortened) }

    public var title: String { "Leaving \(Self.time(ready)): \(percent)%" }

    public var detail: String {
        switch outcome {
        case .willStart(let at):
            return "Charging starts around \(Self.time(at)), so you're at \(percent)% when you leave. Your zone limit pauses until then."
        case .startingNow:
            return "Charging is starting now to reach \(percent)% by \(Self.time(ready))."
        case .needsPower(let by):
            return "Plug in by \(Self.time(by)) so it can reach \(percent)% by \(Self.time(ready))."
        case .blockedByZone(let zone, let active):
            return "This is set for \(ChangeEvent.zoneName(zone)) only, but \(ChangeEvent.zoneName(active)) is active, so it won't charge. Be in \(ChangeEvent.zoneName(zone)) by the start time, or choose Anywhere in Ready by."
        case .tooHot(let t):
            return String(format: "The battery is %.0f °C and a top-up pauses above %d °C. Let it cool, or keep the Mac somewhere cooler, so it can reach %d%% by %@.",
                          t, HeatLimit.ratedChargeMax, percent, Self.time(ready))
        case .alreadyThere:
            return "Already at \(percent)% or more, so nothing needs to charge."
        }
    }
}
