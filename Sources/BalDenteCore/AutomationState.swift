import Foundation

/// Plain names for what BalDente is doing, for the `baldente get state` command that Shortcuts scripts call.
public enum AutomationState {
    public static func name(_ s: Status) -> String {
        let t = s.state.task
        switch t.kind {
        case "topup": return "Topup"
        case "calibrate": return "Calibration"
        case "discharge": return "Discharging"
        default: break
        }
        if s.heatHold { return "HeatProtect" }
        if !s.state.enabled { return "Charging" }
        if !s.adapterOn { return s.percent < s.state.upper ? "Sailing" : "Pause" }   // held inside the range vs held at the limit
        return "Charging"
    }

    /// The value for `baldente get <what>`, nil for an unknown name.
    public static func value(_ what: String, _ s: Status) -> String? {
        switch what {
        case "state": return name(s)
        case "percent": return String(s.percent)
        case "limit": return String(s.state.upper)
        case "temperature": return s.tempC.map { String(format: "%.1f", $0) } ?? "unknown"
        case "zone": return s.state.label
        default: return nil
        }
    }
}
