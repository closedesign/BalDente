import Foundation

/// Animation clock for the charging effect. It adds up elapsed time times the current speed, so moving the speed slider
/// changes how fast everything runs from that moment on instead of making it jump to a different spot.
public struct WaveClock {
    /// The raw clock rate for the "1×" setting. The first release ran 1× at full rate, which looked too fast.
    public static let baseline = 0.5
    public static let speedRange = 0.1...3.0

    /// The clock rate for a speed setting as shown in the UI (1× = `baseline`), kept inside `speedRange`.
    public static func rate(forSetting setting: Double) -> Double {
        min(speedRange.upperBound, max(speedRange.lowerBound, (setting.isFinite ? setting : 1) * baseline))
    }
    /// Seconds of animation time that have passed (real seconds times speed).
    public private(set) var elapsed = 0.0
    private var last: Date?

    public init() {}

    /// Advances the clock and returns the wave position in 0..<1, one full ripple every `cycle` animation seconds.
    @discardableResult
    public mutating func advance(now: Date, speed: Double, cycle: TimeInterval) -> Double {
        let s = min(Self.speedRange.upperBound, max(Self.speedRange.lowerBound, speed.isFinite ? speed : 1))
        // A long gap (display asleep, animation stopped) must not make the animation spin.
        let dt = last.map { min(0.25, max(0, now.timeIntervalSince($0))) } ?? 0
        last = now
        elapsed += dt * s
        return cycle > 0 ? (elapsed / cycle).truncatingRemainder(dividingBy: 1) : 0
    }
}
