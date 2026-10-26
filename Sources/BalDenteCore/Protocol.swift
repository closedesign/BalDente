import Foundation

public let socketPath = "/var/run/baldente.sock"
public let stateDir = "/Library/Application Support/BalDente"
public let statePath = stateDir + "/state.json"

public struct Schedule: Codable, Equatable {
    public var enabled = false
    public var days = [1]          // days of month
    public var hour = 21
    public var minute = 30
    public var lastRun: String?    // yyyy-MM-dd, so a run happens once per day
    public init() {}

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        days = try c.decodeIfPresent([Int].self, forKey: .days) ?? [1]
        hour = try c.decodeIfPresent(Int.self, forKey: .hour) ?? 21
        minute = try c.decodeIfPresent(Int.self, forKey: .minute) ?? 30
        lastRun = try c.decodeIfPresent(String.self, forKey: .lastRun)
    }
}

/// The next time the clock shows hour:minute, today if it hasn't passed yet, otherwise tomorrow.
public func nextOccurrence(hour: Int, minute: Int, after now: Date, calendar cal: Calendar = .current) -> Date? {
    guard let today = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now) else { return nil }
    return today > now ? today : cal.date(byAdding: .day, value: 1, to: today)
}

/// Whether a day-of-month schedule fires today. A day past the end of a short month (31 in April, 29 in a common February)
/// fires on the month's last day instead of being skipped.
public func scheduleDayMatches(days: [Int], today: Int, daysInMonth: Int) -> Bool {
    days.contains { min($0, daysInMonth) == today }
}

public func dayString(_ d: Date) -> String {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
}

/// One "be ready by" moment: a weekday (1 = Sunday ... 7 = Saturday), a time and a target charge level.
public struct Slot: Codable, Equatable {
    public var weekday: Int
    public var hour: Int
    public var minute: Int
    public var percent: Int
    public init(weekday: Int, hour: Int, minute: Int, percent: Int = 100) {
        self.weekday = weekday; self.hour = hour; self.minute = minute; self.percent = percent
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        weekday = try c.decode(Int.self, forKey: .weekday)
        hour = try c.decode(Int.self, forKey: .hour)
        minute = try c.decode(Int.self, forKey: .minute)
        percent = try c.decodeIfPresent(Int.self, forKey: .percent) ?? 100   // older saves had no level
    }
}

/// "Be at 100% by this time", each weekday with its own time, e.g. before leaving for school.
public struct ChargeSchedule: Codable, Equatable {
    public var enabled = false
    public var slots: [Slot] = [2, 3, 4, 5, 6].map { Slot(weekday: $0, hour: 7, minute: 30) }
    /// Departure moments we already charged for (see `key`), so each runs once.
    public var ran: [String] = []
    public var wakeAt: String?              // wake we scheduled with pmset, so we can replace it
    /// Only run while this zone is active (nil = anywhere).
    public var onlyZone: String?
    public init() {}

    private enum Legacy: String, CodingKey { case weekdays, hour, minute }

    // Older state files had one shared time for a list of weekdays; turn that into slots.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        ran = try c.decodeIfPresent([String].self, forKey: .ran) ?? []
        wakeAt = try c.decodeIfPresent(String.self, forKey: .wakeAt)
        onlyZone = try c.decodeIfPresent(String.self, forKey: .onlyZone)
        if let s = try c.decodeIfPresent([Slot].self, forKey: .slots) { slots = s }
        else {
            let l = try d.container(keyedBy: Legacy.self)
            if let days = try l.decodeIfPresent([Int].self, forKey: .weekdays) {
                let h = try l.decodeIfPresent(Int.self, forKey: .hour) ?? 7, m = try l.decodeIfPresent(Int.self, forKey: .minute) ?? 30
                slots = days.map { Slot(weekday: $0, hour: h, minute: m) }
            }
        }
    }

    public static func key(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm"; return f.string(from: d)
    }

    /// Rough time to charge from `percent` to 100%, plus a safety buffer.
    public static func leadMinutes(percent: Int, target: Int = 100) -> Double { Double(max(0, target - percent)) * 1.5 + 10 }

    /// The next departure that still needs a charge, with the slot it came from.
    public func nextSlot(after now: Date, calendar cal: Calendar = .current) -> (ready: Date, slot: Slot)? {
        guard enabled else { return nil }
        for off in 0...7 {
            guard let day = cal.date(byAdding: .day, value: off, to: now) else { continue }
            let wd = cal.component(.weekday, from: day)
            let found = slots.filter { $0.weekday == wd }.compactMap { s -> (Date, Slot)? in
                guard let r = cal.date(bySettingHour: s.hour, minute: s.minute, second: 0, of: day),
                      r > now, !ran.contains(Self.key(r)) else { return nil }
                return (r, s)
            }
            if let first = found.min(by: { $0.0 < $1.0 }) { return (ready: first.0, slot: first.1) }
        }
        return nil
    }

    public func nextReady(after now: Date, calendar cal: Calendar = .current) -> Date? { nextSlot(after: now, calendar: cal)?.ready }
}

/// A timed job the daemon runs on top of the normal limiter.
public struct TaskState: Codable, Equatable {
    public var kind = "none"       // none | discharge | calibrate | topup
    public var phase = ""          // calibrate: discharge | charge | rest
    public var target = 0
    public var restUntil: Date?
    public init() {}
    public var active: Bool { kind != "none" }
}

/// What the daemon should enforce. Zone detection runs in the user session
/// and just sends the resulting limits here.
public struct LimiterState: Codable, Equatable {
    public var enabled = true
    public var upper = 80
    public var lower = 75
    public var label = "default"
    public var heatProtection = true
    public var heatLimit = HeatLimit.defaultLimit
    public var lowPower = false
    public var schedule = Schedule()
    public var chargeSchedule = ChargeSchedule()
    /// One-off calibration planned for a specific moment, e.g. tonight at 3 AM.
    public var calibrateAt: Date?
    public var task = TaskState()
    public init() {}

    // Old state files lack newer keys; keep their values and default the rest.
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        upper = try c.decodeIfPresent(Int.self, forKey: .upper) ?? 80
        lower = try c.decodeIfPresent(Int.self, forKey: .lower) ?? 75
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? "default"
        heatProtection = try c.decodeIfPresent(Bool.self, forKey: .heatProtection) ?? true
        heatLimit = try c.decodeIfPresent(Int.self, forKey: .heatLimit) ?? HeatLimit.defaultLimit
        lowPower = try c.decodeIfPresent(Bool.self, forKey: .lowPower) ?? false
        schedule = try c.decodeIfPresent(Schedule.self, forKey: .schedule) ?? Schedule()
        chargeSchedule = try c.decodeIfPresent(ChargeSchedule.self, forKey: .chargeSchedule) ?? ChargeSchedule()
        calibrateAt = try c.decodeIfPresent(Date.self, forKey: .calibrateAt)
        task = try c.decodeIfPresent(TaskState.self, forKey: .task) ?? TaskState()
    }
}

public struct Status: Codable {
    public var percent: Int
    public var adapterOn: Bool
    public var state: LimiterState
    public var backend: String
    public var tempC: Double?
    public var heatHold = false

    public init(percent: Int, adapterOn: Bool, state: LimiterState, backend: String, tempC: Double? = nil, heatHold: Bool = false) {
        self.percent = percent; self.adapterOn = adapterOn; self.state = state; self.backend = backend
        self.tempC = tempC; self.heatHold = heatHold
    }
}
