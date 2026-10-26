import Foundation

/// Plain-language progress for a running calibration (drain to 15%, charge to 100%, rest an hour).
public enum CalibrationProgress {
    public static let drainTarget = 15

    /// True when a calibration ended by running its full course (the rest hour elapsed), not because someone cancelled it.
    /// The helper only reports the task disappearing, so the rest deadline is the evidence; the slack covers the 20 s refresh.
    public static func finishedCleanly(_ was: TaskState, now: Date = Date()) -> Bool {
        guard was.kind == "calibrate", was.phase == "rest", let until = was.restUntil else { return false }
        return now >= until.addingTimeInterval(-60)
    }

    /// "Last calibrated Oct 25", or nil if none has been recorded.
    public static func lastText(_ date: Date?) -> String? {
        date.map { "Last calibrated " + $0.formatted(date: .abbreviated, time: .omitted) }
    }

    /// "Step 1 of 3: draining, 42% now (15% to go)". Nil when the task isn't a calibration.
    public static func text(_ t: TaskState, percent: Int, now: Date = Date()) -> String? {
        guard t.kind == "calibrate" else { return nil }
        switch t.phase {
        case "discharge":
            let left = max(0, percent - drainTarget)
            return "Step 1 of 3: draining, \(percent)% now" + (left > 0 ? " (\(left)% to go)" : "")
        case "charge":
            return "Step 2 of 3: charging, \(percent)% now (\(max(0, 100 - percent))% to go)"
        default:
            guard let until = t.restUntil else { return "Step 3 of 3: resting at 100%" }
            let mins = max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
            return "Step 3 of 3: resting, \(mins) min left"
        }
    }
}
