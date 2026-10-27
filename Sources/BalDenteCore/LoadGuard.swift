import Foundation

/// Cutting the charger runs the Mac from its battery, which hurts most while the CPU is busy (a build, an export).
/// So when the Mac is busy and the battery is only just at its limit, the helper leaves the charger on for a point or two more.
public enum LoadGuard {
    /// One-minute load average per core at or above which the Mac counts as busy.
    public static let busyPerCore = 0.6
    /// How far past the limit the charger may stay on while busy. At `upper + maxOvershoot` it is cut regardless.
    public static let maxOvershoot = 2

    public static func busy(load1: Double, cores: Int) -> Bool {
        cores > 0 && load1 / Double(cores) >= busyPerCore
    }

    /// True when the charger should stay on although `percent` has reached `upper`.
    public static func keepCharging(enabled: Bool, load1: Double, cores: Int, percent: Int, upper: Int) -> Bool {
        enabled && percent >= upper && percent < upper + maxOvershoot && busy(load1: load1, cores: cores)
    }
}

/// SMC keys that, on other Macs, stop charging without cutting power to the Mac. None of them can be used on this Mac today
/// (missing or refused even for root), so the helper only reports which ones read OK, to notice if a macOS update opens them up.
public enum ChargeKeys {
    public static let watched = ["bfF0", "bfD0", "bfE0", "CHTE", "CH0B", "CH0C"]
}
