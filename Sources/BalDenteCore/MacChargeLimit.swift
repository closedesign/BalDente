import Foundation

/// macOS has its own charge limit (System Settings > Battery: 80, 85, 90, 95 or 100%). It is enforced in firmware, so at the
/// limit the Mac runs from the charger instead of the battery, which BalDente can't do (it can only cut the charger).
/// BalDente reads the setting from `pmset -g battlimit` (see `parse`), or the user can pick the step by hand, and matching zones are handed to macOS.
public enum MacChargeLimit {
    public static let steps = [80, 85, 90, 95]

    public enum Role: Equatable {
        /// The zone limit equals macOS's: macOS holds it and the Mac runs from the charger, so BalDente doesn't cut.
        case macOSHolds
        /// The zone wants more than macOS allows: macOS would stop charging early, so its limit has to be raised.
        case blocked
        /// The zone is under macOS's limit (or macOS's limit isn't used): BalDente holds it by cutting the charger.
        case appHolds
    }

    public static func role(upper: Int, macLimit: Int?) -> Role {
        guard let m = macLimit, steps.contains(m) else { return .appHolds }
        if upper == m { return .macOSHolds }
        return upper > m ? .blocked : .appHolds
    }

    /// What the helper is told. A zone macOS holds is sent as "no limit", so BalDente never cuts the charger there.
    public static func sending(_ t: Target, macLimit: Int?) -> Target {
        guard role(upper: t.upper, macLimit: macLimit) == .macOSHolds else { return t }
        var s = t
        s.upper = 100; s.lower = 99
        return s
    }

    /// The setting the user should pick in macOS so a zone of `upper` isn't cut short: the next step at or above it, 100 for none.
    public static func neededSetting(for upper: Int) -> Int { steps.first { $0 >= upper } ?? 100 }

    /// The limit macOS reports in `pmset -g battlimit`: the lowest `chargeSocLimitSoc` of the live manual-limit entries that is one
    /// of macOS's steps. Nil when there is no entry (the limit is off, i.e. 100%).
    public static func parse(_ output: String) -> Int? {
        var found: [Int] = []
        var soc: Int?, manual = false, terminated = false
        func close() { if let s = soc, manual, !terminated, steps.contains(s) { found.append(s) }; soc = nil; manual = false; terminated = false }
        for raw in output.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("}") { close(); continue }
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " ;")) }
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "chargeSocLimitSoc": soc = Int(parts[1])
            case "chargeSocLimitReason": manual = parts[1] == "manualChargeLimit"
            case "Terminated": terminated = parts[1] != "0"
            default: break
            }
        }
        return found.min()
    }
}
