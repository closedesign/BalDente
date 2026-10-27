import Foundation

/// How long a calibration's drain step should take, and when "Calibrate overnight" starts one. UI-free so it is tested.
public enum CalibrationPlan {
    /// Hours to drain from `percent` to 15% at `watts` of power use, or nil without enough data (or almost no load).
    /// The battery's energy is `maxMAh` at `volts`; `watts` is what the Mac draws (sign ignored).
    public static func drainHours(percent: Int, maxMAh: Int?, volts: Double, watts: Double) -> Double? {
        guard let mah = maxMAh, mah > 0, volts > 1, abs(watts) >= 1 else { return nil }
        let left = Double(max(0, percent - CalibrationProgress.drainTarget)) / 100
        return left * Double(mah) * volts / 1000 / abs(watts)
    }

    /// "about 4 h", "about 45 min", "under 10 min".
    public static func durationText(hours: Double) -> String {
        let mins = Int((hours * 60).rounded())
        if mins < 10 { return "under 10 min" }
        if mins < 60 { return "about \((mins + 2) / 5 * 5) min" }
        let h = hours.rounded(.toNearestOrAwayFromZero)
        return h >= 24 ? "more than a day" : "about \(Int(max(1, h))) h"
    }

    public static let nightHours = [22, 23, 0, 1, 2, 3, 4]
    /// Overnight calibration runs at most this often, counted from the last completed one.
    public static let overnightEvery: TimeInterval = 30 * 86400

    /// True when "Calibrate overnight" should start a calibration now: plugged in at night, nothing else running, the last
    /// completed calibration is a month old, and it hasn't already tried tonight (so cancelling it sticks).
    public static func overnightShouldStart(enabled: Bool, plugged: Bool, taskActive: Bool, lastCalibrated: Date?,
                                            lastAttempt: Date?, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard enabled, plugged, !taskActive, nightHours.contains(calendar.component(.hour, from: now)) else { return false }
        if let a = lastAttempt, now.timeIntervalSince(a) < 20 * 3600, now >= a { return false }
        if let l = lastCalibrated, now.timeIntervalSince(l) < overnightEvery { return false }
        return true
    }
}
