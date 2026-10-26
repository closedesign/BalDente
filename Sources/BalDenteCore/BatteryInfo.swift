import Foundation
import IOKit

/// Read-only battery facts from the IORegistry; no root needed.
public struct BatteryInfo {
    public var cycles = 0
    public var healthPercent: Int?
    public var designMAh: Int?
    public var maxMAh: Int?
    public var volts = 0.0
    /// Positive while charging, negative while discharging.
    public var watts = 0.0
    public var tempC: Double?
    public var plugged = false
    /// What the battery's own gauge says, to compare with the percentage macOS shows. Nil when this Mac does not expose it.
    public var hardwarePercent: Int?
    public var flow: PowerFlow?

    public static func read() -> BatteryInfo? {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return nil }
        defer { IOObjectRelease(svc) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return nil }
        let bd = d["BatteryData"] as? [String: Any] ?? [:]

        func int(_ v: Any?) -> Int? { (v as? NSNumber)?.intValue }
        func signed(_ v: Any?) -> Int64? {
            guard let n = v as? NSNumber else { return nil }
            return Int64(bitPattern: n.uint64Value)   // negative amps come back as huge unsigned values
        }

        var i = BatteryInfo()
        i.cycles = int(d["CycleCount"]) ?? 0
        i.designMAh = int(bd["DesignCapacity"]) ?? int(d["DesignCapacity"])
        // NominalChargeCapacity is what System Settings reports; older Macs only expose the raw/legacy keys (MaxCapacity is a
        // percent on Apple silicon, mAh on Intel, so only trust it when it is clearly mAh).
        i.maxMAh = int(bd["NominalChargeCapacity"]) ?? int(d["NominalChargeCapacity"]) ?? int(d["AppleRawMaxCapacity"])
            ?? int(d["MaxCapacity"]).flatMap { $0 > 100 ? $0 : nil }
        if let design = i.designMAh, let mx = i.maxMAh, design > 0 { i.healthPercent = min(100, Int((Double(mx) * 100 / Double(design)).rounded())) }
        // The gauge's remaining charge over its full-charge capacity. macOS rounds and smooths this, so the two differ by a few points.
        if let rem = int(bd["RemainingCapacity"]) ?? int(d["AppleRawCurrentCapacity"]),
           let full = int(bd["FullChargeCapacity"]) ?? int(d["AppleRawMaxCapacity"]), full > 0, rem >= 0 {
            i.hardwarePercent = min(100, Int((Double(rem) * 100 / Double(full)).rounded()))
        }
        if let t = d["PowerTelemetryData"] as? [String: Any] {
            func u(_ v: Any?) -> UInt64? { (v as? NSNumber)?.uint64Value }
            if let pin = u(t["SystemPowerIn"]), let load = u(t["SystemLoad"]), let bat = u(t["BatteryPower"]) {
                i.flow = PowerFlow(systemPowerInMW: pin, systemLoadMW: load, batteryPowerMW: bat)
            }
        }
        i.volts = Double(int(d["Voltage"]) ?? 0) / 1000
        if let a = signed(d["Amperage"]) { i.watts = i.volts * Double(a) / 1000 }
        i.plugged = (d["ExternalConnected"] as? Bool) ?? false
        // Recent macOS reports the amperage as a magnitude; with nothing plugged in the battery can only be discharging.
        if !i.plugged, i.watts > 0 { i.watts = -i.watts }
        if let t = int(d["Temperature"]) { i.tempC = Double(t) / 100 }
        else { i.tempC = SMC.readFloat("TB0T") }
        return i
    }
}
