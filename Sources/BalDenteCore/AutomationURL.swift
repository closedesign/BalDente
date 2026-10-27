import Foundation

/// `baldente://` links, for Apple Shortcuts ("Open URLs"), Terminal and other automation. Any web page can open one, so only
/// reversible actions exist, targets are range-checked, and the app logs every one it runs.
public enum AutomationAction: Equatable {
    case topUp(Bool)
    case travel(Bool)
    case discharge(to: Int)
    case calibrate
    case lowPower(Bool)
    case automatic          // un-pin a zone
    case cancelTask
    case pinZone(String)    // pin a zone by name (matched case-insensitively by the app)

    public var title: String {
        switch self {
        case .topUp(let on): on ? "Top Up" : "Cancel Top Up"
        case .travel(let on): on ? "Travel mode on" : "Travel mode off"
        case .discharge(let t): "Discharge to \(t)%"
        case .calibrate: "Calibrate"
        case .lowPower(let on): on ? "Low Power Mode on" : "Low Power Mode off"
        case .automatic: "Automatic zone"
        case .cancelTask: "Cancel task"
        case .pinZone(let n): "Pin zone \(n)"
        }
    }
}

public enum AutomationURL {
    public static let scheme = "baldente"

    /// `baldente://topup`, `topup/off`, `travel/on|off`, `discharge/50`, `calibrate`, `lowpower/on|off`, `automatic`, `cancel`, `zone/<name>`.
    public static func parse(_ url: URL) -> AutomationAction? {
        guard url.scheme?.lowercased() == scheme, let host = url.host?.lowercased() else { return nil }
        let arg = url.pathComponents.dropFirst().first?.lowercased()
        func flag(_ a: String?) -> Bool? { a == nil || a == "on" ? true : a == "off" ? false : nil }
        switch host {
        case "topup": return flag(arg).map(AutomationAction.topUp)
        case "travel": return flag(arg).map(AutomationAction.travel)
        case "lowpower": return arg.flatMap { ["on", "off"].contains($0) ? AutomationAction.lowPower($0 == "on") : nil }
        case "discharge":
            guard let t = arg.flatMap(Int.init), (AutoDischarge.minimumTarget...90).contains(t) else { return nil }
            return .discharge(to: t)
        case "calibrate": return .calibrate
        case "automatic": return .automatic
        case "cancel": return .cancelTask
        case "zone":
            guard let n = arg.map({ _ in url.pathComponents.dropFirst().first ?? "" }), !n.isEmpty, n.count <= 40,
                  !n.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            return .pinZone(n)
        default: return nil
        }
    }
}
