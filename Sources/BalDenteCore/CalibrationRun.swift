import Foundation

/// The helper's calibration state machine: drain to 15%, charge to 100%, rest an hour. UI-free so it is tested.
public enum CalibrationRun {
    /// Some batteries stall at 98-99% for hours, so the charge step also ends after this long at 98% or more.
    public static let chargeStallLimit: TimeInterval = 2 * 3600
    /// A calibration that hasn't finished after this long (unplugged mid-charge, a Mac that never drains) gives up.
    public static let maxDuration: TimeInterval = 24 * 3600
    public static let restLength: TimeInterval = 3600
    /// A planned or repeating calibration is skipped when one finished this recently.
    public static let recentWindow: TimeInterval = 20 * 3600

    public static func start(now: Date = Date()) -> TaskState {
        var t = TaskState(); t.kind = "calibrate"; t.phase = "discharge"; t.started = now; t.phaseStarted = now
        return t
    }

    /// Pauses a running calibration where it is. The normal limits apply until it resumes.
    public static func pause(_ task: TaskState, now: Date = Date()) -> TaskState {
        guard task.kind == "calibrate", task.pausedAt == nil else { return task }
        var t = task; t.pausedAt = now; return t
    }

    /// Picks up where it paused. Every clock moves forward by the pause, so it neither times out nor cuts the rest short.
    public static func resume(_ task: TaskState, now: Date = Date()) -> TaskState {
        guard task.kind == "calibrate", let p = task.pausedAt else { return task }
        var t = task; let gap = max(0, now.timeIntervalSince(p))
        t.pausedAt = nil
        t.started = t.started?.addingTimeInterval(gap)
        t.phaseStarted = t.phaseStarted?.addingTimeInterval(gap)
        t.restUntil = t.restUntil?.addingTimeInterval(gap)
        return t
    }

    public enum Outcome: Equatable { case running, finished, timedOut }

    /// Moves a calibration one step. Returns the new task (reset when it ends), whether the charger should be on, and why it ended.
    public static func advance(_ task: TaskState, percent pct: Int, now: Date = Date()) -> (task: TaskState, adapterOn: Bool?, outcome: Outcome) {
        if task.pausedAt != nil { return (task, nil, .running) }
        var t = task
        // Tasks saved by an older helper have no timestamps: start the clocks now rather than timing out at once.
        if t.started == nil { t.started = now }
        if t.phaseStarted == nil { t.phaseStarted = now }
        if let s = t.started, now.timeIntervalSince(s) >= maxDuration { return (TaskState(), nil, .timedOut) }
        switch t.phase {
        case "discharge":
            if pct > CalibrationProgress.drainTarget { return (t, false, .running) }
            t.phase = "charge"; t.phaseStarted = now
            return (t, true, .running)
        case "charge":
            let stalled = pct >= 98 && now.timeIntervalSince(t.phaseStarted ?? now) >= chargeStallLimit
            if pct >= 100 || stalled { t.phase = "rest"; t.phaseStarted = now; t.restUntil = now.addingTimeInterval(restLength) }
            return (t, true, .running)
        default:
            if t.restUntil == nil { t.restUntil = now.addingTimeInterval(restLength) }
            if let until = t.restUntil, now >= until { return (TaskState(), nil, .finished) }
            return (t, true, .running)
        }
    }

    /// True when an automatic (planned or repeating) calibration should be skipped because one just ran.
    public static func ranRecently(_ last: Date?, now: Date = Date()) -> Bool {
        guard let last else { return false }
        return now.timeIntervalSince(last) < recentWindow && now >= last
    }
}
