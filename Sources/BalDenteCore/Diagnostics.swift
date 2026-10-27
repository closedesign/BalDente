import Foundation

/// The text a user pastes into a bug report. It holds versions and states, never Wi-Fi names or places.
public struct DiagnosticsInfo {
    public var appVersion: String
    public var macOS: String
    public var mac: String
    public var helper: String          // "running", "update available", "not responding", "not installed"
    public var backend: String?
    public var percent: Int?
    public var tempC: Double?
    public var limit: String?          // "80% / 75% (Home)"
    public var zoneCount: Int
    public var heatProtection: Bool?
    public var recent: [String]
    public var lastError: String?
    /// Charge-control keys the helper could read (nil: older helper).
    public var chargeKeys: [String]?

    public init(appVersion: String, macOS: String, mac: String, helper: String, backend: String? = nil, percent: Int? = nil,
                tempC: Double? = nil, limit: String? = nil, zoneCount: Int, heatProtection: Bool? = nil,
                recent: [String] = [], lastError: String? = nil, chargeKeys: [String]? = nil) {
        self.appVersion = appVersion; self.macOS = macOS; self.mac = mac; self.helper = helper; self.backend = backend
        self.percent = percent; self.tempC = tempC; self.limit = limit; self.zoneCount = zoneCount
        self.heatProtection = heatProtection; self.recent = recent; self.lastError = lastError; self.chargeKeys = chargeKeys
    }

    public var report: String {
        var l = ["BalDente diagnostics", "App: \(appVersion)", "macOS: \(macOS)", "Mac: \(mac)", "Helper: \(helper)"]
        if let b = backend { l.append("Charging backend: \(b)") }
        if let p = percent { l.append("Battery: \(p)%" + (tempC.map { String(format: ", %.1f °C", $0) } ?? "")) }
        if let x = limit { l.append("Limit: \(x)") }
        if let k = chargeKeys { l.append("Pass-through keys readable: \(k.isEmpty ? "none" : k.joined(separator: ", "))") }
        if let h = heatProtection { l.append("Heat Protection: \(h ? "on" : "off")") }
        l.append("Zones: \(zoneCount)")
        if let e = lastError, !e.isEmpty { l.append("Last error: \(e)") }
        if !recent.isEmpty { l.append("Recent changes:"); l += recent.prefix(10).map { "  - \($0)" } }
        l.append("Helper log: /var/log/baldente.log")
        return l.joined(separator: "\n")
    }
}
