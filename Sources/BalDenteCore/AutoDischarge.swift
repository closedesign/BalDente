import Foundation

/// When Auto Discharge may start a discharge on its own: the limit dropped (a new zone, a lower limit) below the battery level
/// and the charger is in. It never fights another task, a one-off override or an upcoming Ready by.
public enum AutoDischarge {
    /// A battery this far above the limit is worth draining; closer than this is just the limiter's normal drift.
    public static let margin = 3
    /// A Ready by that starts charging within this long makes a discharge pointless.
    public static let readyByQuietHours = 4.0
    public static let minimumTarget = 20

    public static func target(enabled: Bool, plugged: Bool, percent: Int, limitUpper: Int, limitEnabled: Bool, taskActive: Bool,
                              overrideActive: Bool, readyBy: ChargeSchedule, now: Date, calendar: Calendar = .current) -> Int? {
        guard enabled, plugged, limitEnabled, !taskActive, !overrideActive, percent >= 0,
              limitUpper >= minimumTarget, percent >= limitUpper + margin else { return nil }
        if let next = readyBy.nextSlot(after: now, calendar: calendar),
           next.ready.timeIntervalSince(now) < readyByQuietHours * 3600 { return nil }
        return limitUpper
    }
}
