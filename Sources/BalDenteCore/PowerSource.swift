import Foundation

/// Where the Mac's power comes from right now, worded like the macOS battery menu ("Power Source: Power Adapter" / "Battery").
/// A Mac that is plugged in but not charging (macOS's own Charge Limit, a full battery, or a BalDente hold) is running
/// from the adapter, so it says "Using AC power" rather than "Charging".
public struct PowerSourceState: Equatable {
    public enum Phase: Equatable { case battery, charging, held, adapter }

    public let onBattery: Bool
    public let charging: Bool
    public let charged: Bool
    public let held: Bool
    public let percent: Int
    public let upper: Int

    public init(onBattery: Bool, charging: Bool, charged: Bool, held: Bool, percent: Int, upper: Int) {
        self.onBattery = onBattery; self.charging = charging; self.charged = charged
        self.held = held; self.percent = percent; self.upper = upper
    }

    public var phase: Phase {
        if onBattery { return .battery }
        if held { return .held }
        if charging && !charged { return .charging }
        return .adapter
    }

    /// "Battery" or "Power Adapter", as in the macOS battery menu.
    public var sourceName: String { phase == .battery ? "Battery" : "Power Adapter" }

    public func headline(upper: Int, percent: Int) -> String {
        switch phase {
        case .battery: return "On battery"
        case .held: return "Holding at \(percent)%"
        case .charging: return "Charging to \(upper)%"
        case .adapter: return "Using AC power"
        }
    }

    /// Caption inside the battery rings; `compact` is a shorter one for the small (about 80 pt wide) rings.
    public func caption(compact: Bool) -> (text: String, icon: String) {
        switch phase {
        case .battery: return (compact ? "Battery" : "On battery", "battery.75percent")
        case .held: return ("Holding", "pause.fill")
        case .charging: return ("Charging", "bolt.fill")
        case .adapter: return (compact ? "AC power" : "Using AC power", "powerplug.fill")
        }
    }
}
