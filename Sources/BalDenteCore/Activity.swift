import Foundation

/// Groups of announcements the user can mute separately. The activity log records every one regardless.
public enum NotifyCategory: String, Codable, CaseIterable, Identifiable {
    case zones, readyBy, heat, habits, manual, helper
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .zones: "Zone switches"
        case .readyBy: "Ready by and calendar top-ups"
        case .heat: "Heat Protection"
        case .habits: "Habit and zone suggestions"
        case .manual: "Top Up, Travel mode and tasks"
        case .helper: "Helper problems"
        }
    }
}

/// Every change BalDente announces, with its reason. Wording lives here so notifications and the log always agree.
public enum ChangeEvent: Equatable {
    /// The active limit changed. `from` is the previous label; `reason` says why (e.g. "Wi-Fi HomeNet", "pinned").
    case limit(from: String, to: String, upper: Int, lower: Int, reason: String?)
    case readyByStarted(percent: Int, by: Date?, calendar: Bool)
    case readyByFinished(calendar: Bool, backTo: String)
    case heat(on: Bool, limit: Int)
    case habitSuggested(String)
    case networkSuggested(String)
    case habitAccepted(String)
    case task(started: Bool, kind: String, target: Int)
    case defaultsChosen(String)
    case helperOffline
    case helperBack

    public var category: NotifyCategory {
        switch self {
        case .limit(_, let to, _, _, _): ChangeEvent.manualLabels.contains(to) ? .manual : .zones
        case .readyByStarted, .readyByFinished: .readyBy
        case .heat: .heat
        case .habitSuggested, .habitAccepted, .networkSuggested: .habits
        case .task, .defaultsChosen: .manual
        case .helperOffline, .helperBack: .helper
        }
    }

    /// Labels the app sends for one-off overrides rather than zones.
    public static let manualLabels: Set<String> = ["Top Up", "Travel Mode"]

    static func zoneName(_ label: String) -> String { label == "Default" ? "Everywhere else" : label }

    public var title: String {
        switch self {
        case .limit(let from, let to, let upper, _, _):
            if to == "Top Up" { return "Topping up to 100%" }
            if to == "Travel Mode" { return "Travel mode: holding 100%" }
            if ChangeEvent.manualLabels.contains(from) { return "Back to \(ChangeEvent.zoneName(to)): \(upper)%" }
            return "Switched to \(ChangeEvent.zoneName(to)): \(upper)%"
        case .readyByStarted(let p, _, let cal): return "\(cal ? "Calendar Ready by" : "Ready by"): charging to \(p)%"
        case .readyByFinished(let cal, let back): return "\(cal ? "Calendar Ready by" : "Ready by") finished"
            + (back.isEmpty ? "" : ", back to \(ChangeEvent.zoneName(back))")
        case .heat(let on, _): return on ? "Heat protection on" : "Cooled down"
        case .habitSuggested: return "A charge plan for your routine"
        case .networkSuggested: return "A Wi-Fi network you use often"
        case .habitAccepted: return "Ready by set from your routine"
        case .task(let started, let kind, let target):
            switch (kind, started) {
            case ("discharge", true): return "Discharging to \(target)%"
            case ("discharge", false): return "Discharge finished"
            case ("calibrate", true): return "Calibration started"
            case ("calibrate", false): return "Calibration finished"
            default: return started ? "Task started" : "Task finished"
            }
        case .defaultsChosen(let name): return "Limits set: \(name)"
        case .helperOffline: return "BalDente's helper isn't answering"
        case .helperBack: return "Helper is back"
        }
    }

    public var body: String {
        switch self {
        case .limit(let from, let to, let upper, let lower, let reason):
            if to == "Top Up" { return "You asked for a full battery. Your zone limit returns at 100%." }
            if to == "Travel Mode" { return "You turned on Travel mode. It holds 100% for 24 hours, then your zone limit returns." }
            let why: String
            if ChangeEvent.manualLabels.contains(from) { why = from == "Top Up" ? "Top Up finished." : "Travel mode ended." }
            else { why = reason.map { "Because: \($0)." } ?? "" }
            let hold = upper >= 100 ? "Charging to 100%." : "Charging holds at \(upper)%, resumes at \(lower)%."
            return [why, hold].filter { !$0.isEmpty }.joined(separator: " ")
        case .readyByStarted(let p, let by, _):
            let when = by.map { " by \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            return "Zone limits are paused so the battery reaches \(p)%\(when). They return 30 minutes after that, or when you unplug."
        case .readyByFinished: return "The scheduled top-up ended and your normal limit applies again."
        case .heat(let on, let limit):
            return on ? "The battery reached \(limit) °C, so charging is paused until it cools 3 degrees." : "Normal charging can continue."
        case .habitSuggested(let text), .networkSuggested(let text): return text
        case .habitAccepted(let text): return "\(text) Change or turn it off on the Charging Tools page."
        case .task(let started, let kind, _):
            if started { return kind == "discharge" ? "The charger stays off until then." : "Drain to 15%, charge to 100%, rest an hour. Keep it plugged in." }
            return "Your normal limit applies again."
        case .defaultsChosen: return "You can change any zone's limits on the Zones page."
        case .helperOffline: return "Charging limits aren't being applied. Open BalDente > General to reinstall it."
        case .helperBack: return "Charging limits are being applied again."
        }
    }
}

/// One line of the in-app "Recent changes" list.
public struct ActivityEntry: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var date: Date
    public var category: NotifyCategory
    public var title: String
    public var detail: String
    public init(date: Date, category: NotifyCategory, title: String, detail: String) {
        self.date = date; self.category = category; self.title = title; self.detail = detail
    }
    public init(_ e: ChangeEvent, at date: Date) { self.init(date: date, category: e.category, title: e.title, detail: e.body) }
}

/// Newest first, capped, and with repeats collapsed so a flapping Wi-Fi can't flood it.
public struct ActivityLog: Codable, Equatable {
    public private(set) var entries: [ActivityEntry] = []
    public static let cap = 100
    /// The same title within this window replaces the earlier entry instead of adding another.
    public static let coalesceSeconds = 60.0
    public init(entries: [ActivityEntry] = []) { self.entries = Array(entries.sorted { $0.date > $1.date }.prefix(Self.cap)) }

    public mutating func add(_ e: ActivityEntry) {
        if let top = entries.first, top.title == e.title, e.date.timeIntervalSince(top.date) < Self.coalesceSeconds { entries.removeFirst() }
        entries.insert(e, at: 0)
        if entries.count > Self.cap { entries.removeLast(entries.count - Self.cap) }
    }

    public mutating func clear() { entries = [] }

    public static var url: URL { Config.url.deletingLastPathComponent().appendingPathComponent("activity.json") }

    public static func load(from url: URL = url) -> ActivityLog {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(ActivityLog.self, from: $0) }.map { ActivityLog(entries: $0.entries) } ?? ActivityLog()
    }

    public func save(to url: URL = url) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let d = try? JSONEncoder().encode(self) { try? d.write(to: url, options: .atomic) }
    }

    /// "Today", "Yesterday" or a date, for grouping rows.
    public static func dayHeading(_ d: Date, now: Date = Date(), calendar cal: Calendar = .current) -> String {
        if cal.isDate(d, inSameDayAs: now) { return "Today" }
        if let y = cal.date(byAdding: .day, value: -1, to: now), cal.isDate(d, inSameDayAs: y) { return "Yesterday" }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}
