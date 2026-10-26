import Foundation

/// What a fresh install does, in plain words, and the one choice offered on first run. Values are read from `Config()`
/// and `HeatLimit`, never typed into UI text, so the tutorial can't drift from the real defaults.
public enum Defaults {
    public struct Line: Equatable, Identifiable {
        public var name: String
        public var upper: Int
        public var lower: Int
        public var id: String { name }
        public var text: String { upper >= 100 ? "\(name): charges to 100%" : "\(name): holds at \(upper)%, resumes at \(lower)%" }
    }

    public static func lines(_ c: Config = Config()) -> [Line] {
        c.zones.map { Line(name: $0.name, upper: $0.upper, lower: $0.lower) }
            + [Line(name: "Everywhere else", upper: c.defaultUpper, lower: c.defaultLower)]
    }

    public static var heatText: String { "Heat Protection pauses charging above \(HeatLimit.defaultLimit) °C." }

    /// The first-run choices. Only these two exist; any other preset is a product decision to make first.
    public enum Preset: String, CaseIterable, Identifiable {
        case keep, everywhere80
        public var id: String { rawValue }
        public var title: String { self == .keep ? "Keep the zone defaults" : "80% everywhere" }
        public var detail: String {
            self == .keep ? "Different limits per place. Home applies once you add your home Wi-Fi."
                          : "One simple limit for every zone and everywhere else: hold at 80%, resume at 75%."
        }
    }

    /// Applies a preset to a config. "80% everywhere" keeps zones (names, Wi-Fi, places) and only changes their limits.
    public static func apply(_ p: Preset, to c: Config) -> Config {
        guard p == .everywhere80 else { return c }
        var c = c
        for i in c.zones.indices { c.zones[i].upper = 80; c.zones[i].lower = 75 }
        c.defaultUpper = 80; c.defaultLower = 75
        return c
    }
}

/// The quiet "why isn't it full?" hint shown while charging is held below 100%.
public struct HoldHint: Codable, Equatable {
    public var dismissed = false
    /// Times the user used Top Up or Ready by; after `enoughUses` they clearly know, so the hint retires.
    public var uses = 0
    public static let enoughUses = 3
    public init() {}

    public var retired: Bool { dismissed || uses >= Self.enoughUses }

    /// The hint text, or nil when there's nothing worth saying.
    /// - Parameters:
    ///   - label: the active target's label ("Home", "Default", "Top Up"...).
    ///   - helperRunning: false while the helper is missing or silent; then no limit applies at all, so no hint.
    ///   - zonesMatched: whether any zone (Wi-Fi or place) matched; false means "Everywhere else" is in charge.
    ///   - locationAllowed: without it Wi-Fi names are hidden, so a Home zone set up by name can't match yet.
    ///   - onBattery: unplugged, so nothing is "held"; the hint says where charging will stop instead.
    public func message(label: String, upper: Int, helperRunning: Bool, zonesMatched: Bool, locationAllowed: Bool, onBattery: Bool = false) -> String? {
        guard !retired, helperRunning, upper < 100, !ChangeEvent.manualLabels.contains(label) else { return nil }
        let place = label == "Default" ? "no zone matched, so Everywhere else applies" : "\(label) zone"
        var text = "\(onBattery ? "Charging will stop at" : "Holding at") \(upper)% (\(place)). Need a full battery?"
        if !zonesMatched && !locationAllowed { text += " Allow Location so BalDente can see your Wi-Fi and pick the right zone." }
        return text
    }
}

/// The tutorial's stored state. Bump `current` when the tour changes enough to show it again.
public enum TutorialVersion {
    public static let current = 1
    /// A new install sees it; so does anyone who saw an older tour. Upgraders from before the tour existed get What's New instead.
    public static func shouldShow(seen: Int, firstLaunch: Bool) -> Bool { seen < current && (firstLaunch || seen > 0) }
}

/// "Charge normally for…": a timed Travel Mode (100%), so it needs nothing new from the helper and ends on its own.
public enum LimitPause {
    public static let options: [(label: String, hours: Int)] = [("1 hour", 1), ("2 hours", 2), ("4 hours", 4), ("24 hours", 24)]

    public static func end(hours: Int, from now: Date) -> Date { now.addingTimeInterval(TimeInterval(max(1, hours)) * 3600) }

    /// "until 3:40 PM", or "until Tue 3:40 PM" when it ends on another day.
    public static func untilText(_ end: Date, now: Date, calendar: Calendar = .current) -> String {
        let f = DateFormatter()
        f.locale = calendar.locale ?? .current
        f.timeZone = calendar.timeZone
        f.setLocalizedDateFormatFromTemplate(calendar.isDate(end, inSameDayAs: now) ? "jmm" : "EEEjmm")
        return "until " + f.string(from: end)
    }
}
