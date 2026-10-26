import Foundation

/// Where power is going right now, in watts, from the battery's power telemetry. Read-only.
/// Every value is non-negative; `fromBattery` and `toBattery` are never both above zero.
public struct PowerFlow: Equatable {
    public var fromCharger: Double
    public var fromBattery: Double
    public var toMac: Double
    public var toBattery: Double

    public init(fromCharger: Double, fromBattery: Double, toMac: Double, toBattery: Double) {
        self.fromCharger = fromCharger; self.fromBattery = fromBattery; self.toMac = toMac; self.toBattery = toBattery
    }

    /// `systemPowerIn`, `systemLoad` and `batteryPower` are the milliwatt readings from `PowerTelemetryData`.
    /// Battery power is signed (negative while discharging) and arrives as a wrapped unsigned number, so it is reinterpreted here.
    public init(systemPowerInMW: UInt64, systemLoadMW: UInt64, batteryPowerMW: UInt64) {
        let battery = Double(Int64(bitPattern: batteryPowerMW)) / 1000
        // A wrapped "negative" input would be a huge positive: treat anything absurd (over 500 W) as no reading.
        func watts(_ v: UInt64) -> Double { let w = Double(Int64(bitPattern: v)) / 1000; return (w < 0 || w > 500) ? 0 : w }
        self.init(fromCharger: watts(systemPowerInMW), fromBattery: max(0, -battery),
                  toMac: watts(systemLoadMW), toBattery: max(0, battery))
    }

    public var isIdle: Bool { fromCharger < 0.05 && fromBattery < 0.05 }

    /// One line, e.g. "Charger 61 W: Mac 22 W, battery 39 W".
    public var summary: String {
        func w(_ v: Double) -> String { String(format: v < 10 ? "%.1f W" : "%.0f W", v) }
        if fromBattery >= 0.05 {
            return fromCharger >= 0.05 ? "Charger \(w(fromCharger)) and battery \(w(fromBattery)) power the Mac (\(w(toMac)))"
                                       : "Battery powers the Mac: \(w(fromBattery))"
        }
        if fromCharger < 0.05 { return "No power flowing" }
        return toBattery >= 0.05 ? "Charger \(w(fromCharger)): Mac \(w(toMac)), battery \(w(toBattery))"
                                 : "Charger \(w(fromCharger)) powers the Mac (\(w(toMac)))"
    }
}
