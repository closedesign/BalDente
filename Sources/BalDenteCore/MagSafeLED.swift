import Foundation

/// The MagSafe LED, driven through the `ACLC` SMC key. Only the four values below are ever written;
/// 0 hands control back to the system. Values were checked by reading `ACLC` with `smcprobe`, writes need testing per Mac model.
public enum LEDColor: String, Codable, CaseIterable, Identifiable {
    case system, off, green, orange
    public var id: String { rawValue }
    public var title: String { self == .system ? "Default" : rawValue.capitalized }
    /// The byte written to `ACLC`; 0 gives the LED back to macOS.
    public var byte: UInt8 { switch self { case .system: 0; case .off: 1; case .green: 3; case .orange: 4 } }
}

public enum MagSafeLED: String, Codable, CaseIterable, Identifiable {
    case system, indicate, custom, off
    public var id: String { rawValue }
    public static let key = "ACLC"
    public static let systemValue: UInt8 = 0

    public var title: String {
        switch self {
        case .system: "Default"
        case .indicate: "Show the limit"
        case .custom: "Custom"
        case .off: "Always off"
        }
    }

    /// The byte to write now, or nil to leave the LED to the system. Green means the limit is reached and the charger is held;
    /// orange means charging (or paused for heat) toward it. Unplugged shows nothing, so there is nothing to write.
    /// `custom` uses the colours you picked for "at the limit" and "charging"; unplugged it leaves the LED to the system.
    public func value(plugged: Bool, holding: Bool, atLimit: LEDColor = .green, charging: LEDColor = .orange) -> UInt8? {
        switch self {
        case .system: return nil
        case .off: return LEDColor.off.byte
        case .indicate: return plugged ? (holding ? LEDColor.green.byte : LEDColor.orange.byte) : nil
        case .custom: return plugged ? (holding ? atLimit.byte : charging.byte) : nil
        }
    }
}
