import Foundation

/// The Heat Protection limit. `baldented` accepts exactly `range` (it uses this same constant), so the
/// UI must never offer or send anything outside it.
public enum HeatLimit {
    /// Cells are only specified to charge up to about 45 °C and firmware cuts charging well before 60 °C,
    /// so anything above 60 would just mean "off".
    public static let range = 30...60
    public static let presets = [35, 40, 45, 50, 60]
    /// Where the pause starts by default. Lithium-ion wear roughly doubles for every 10 °C of cell
    /// temperature and Apple treats 35 °C as the top of the comfortable range, so pausing charge at 35 °C
    /// costs nothing (the Mac runs from the adapter meanwhile) and removes the hottest charging hours.
    public static let defaultLimit = 35
    /// Above this the limit protects little: it is the usual upper cut-off for charging a lithium-ion cell.
    public static let ratedChargeMax = 45

    public static func clamp(_ v: Int) -> Int { min(max(v, range.lowerBound), range.upperBound) }

    /// Turns typed text ("42", "42°", "42 °C") into a valid limit; nil when there is no number.
    public static func parse(_ text: String) -> Int? {
        let digits = text.filter(\.isNumber)
        guard !digits.isEmpty, digits.count <= 3, let v = Int(digits) else { return nil }
        return clamp(v)
    }

    /// 0 at the coolest limit, 1 at the hottest; drives the thermometer position and tint.
    public static func fraction(_ v: Int) -> Double {
        Double(clamp(v) - range.lowerBound) / Double(range.upperBound - range.lowerBound)
    }
}

/// Keyboard entry for the limit: type two digits to set it, or one digit and press Return.
public struct HeatLimitEntry: Equatable {
    public private(set) var digits = ""
    public init() {}

    /// The digit typed so far, shown while waiting for the second one.
    public var pending: String { digits }

    /// Adds a digit; returns the finished limit once two digits are in.
    public mutating func add(_ ch: Character) -> Int? {
        guard ch.isASCII, ch.isNumber else { return nil }
        digits.append(ch)
        guard digits.count >= 2 else { return nil }
        defer { digits = "" }
        return Int(digits).map(HeatLimit.clamp)
    }

    /// Return pressed: accepts a lone digit.
    public mutating func commit() -> Int? {
        defer { digits = "" }
        return Int(digits).map(HeatLimit.clamp)
    }

    public mutating func backspace() { _ = digits.popLast() }
    public mutating func clear() { digits = "" }
}
