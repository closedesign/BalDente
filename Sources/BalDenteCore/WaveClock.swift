import Foundation

/// Phase of the charging wave. It adds up elapsed time times the current speed, so moving the speed slider changes how
/// fast the wave runs from that moment on instead of making it jump to a different spot.
public struct WaveClock {
    public static let speedRange = 0.25...3.0
    public private(set) var phase = 0.0
    private var last: Date?

    public init() {}

    /// - Returns: the wave position in 0..<1, where 1 is one full ripple cycle every `cycle` seconds at 1x.
    public mutating func advance(now: Date, speed: Double, cycle: TimeInterval) -> Double {
        let s = min(Self.speedRange.upperBound, max(Self.speedRange.lowerBound, speed.isFinite ? speed : 1))
        // A long gap (display asleep, animation stopped) must not make the wave spin.
        let dt = last.map { min(0.25, max(0, now.timeIntervalSince($0))) } ?? 0
        last = now
        if cycle > 0 { phase = (phase + dt * s / cycle).truncatingRemainder(dividingBy: 1) }
        return phase
    }
}
