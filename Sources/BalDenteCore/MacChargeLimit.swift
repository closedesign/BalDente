import Foundation

/// macOS has its own charge limit (System Settings > Battery: 80, 85, 90, 95 or 100%). It is enforced in firmware, so at the
/// limit the Mac runs from the charger instead of the battery, which BalDente can't do (it can only cut the charger).
/// BalDente can't read that setting, so the user tells it which step they chose, and it hands matching zones over to macOS.
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
}
