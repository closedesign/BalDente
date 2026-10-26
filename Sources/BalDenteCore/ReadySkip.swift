import Foundation

/// Spots a zone-limited Ready by that should be charging by now but won't, because another limit is active.
/// The helper silently skips such a slot; the app uses this to tell the user once per departure.
public enum ReadySkip {
    public struct Skip: Equatable {
        public var zone: String, active: String, percent: Int, ready: Date
        public var key: String { ChargeSchedule.key(ready) }
    }

    /// `activeLabel` is the label the helper holds (`Target.wireLabel`). Nil when nothing is skipped: no zone restriction,
    /// the zone matches, a task already runs, the battery is already at the target, or the start time has not come yet.
    public static func check(_ cs: ChargeSchedule, activeLabel: String, percent: Int, taskActive: Bool, now: Date,
                             calendar: Calendar = .current) -> Skip? {
        guard let zone = cs.onlyZone, Target.wire(zone) != Target.wire(activeLabel), !taskActive,
              let next = cs.nextSlot(after: now, calendar: calendar), percent >= 0, percent < next.slot.percent else { return nil }
        let start = next.ready.addingTimeInterval(-ChargeSchedule.leadMinutes(percent: percent, target: next.slot.percent) * 60)
        guard now >= start else { return nil }
        return Skip(zone: zone, active: activeLabel, percent: next.slot.percent, ready: next.ready)
    }
}
