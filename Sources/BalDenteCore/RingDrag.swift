import Foundation

/// Dragging the limit and resume-at markers on the Overview ring. 0% is at 12 o'clock and the ring fills clockwise.
public enum RingDrag {
    public enum Handle: Equatable { case upper, lower }

    /// Same ranges as the zone editor's sliders.
    public static let upperRange = 20...100
    public static let lowerRange = 5...99

    /// The percent under a point, given as an offset from the ring's centre in a y-down view.
    /// `previous` keeps the value from jumping across 12 o'clock: dragging past 100 stays at 100 instead of wrapping to 0.
    public static func percent(dx: Double, dy: Double, previous: Int) -> Int {
        var deg = atan2(dx, -dy) * 180 / .pi
        if deg < 0 { deg += 360 }
        let p = Int((deg / 3.6).rounded())
        if abs(p - previous) > 50 { return previous >= 50 ? 100 : 0 }
        return min(100, max(0, p))
    }

    /// Dragged values land on multiples of this, like the zone editor's sliders.
    public static let step = 5

    /// `p` rounded to the nearest multiple of `step`.
    public static func snap(_ p: Int, step: Int = RingDrag.step) -> Int { Int((Double(p) / Double(step)).rounded()) * step }

    /// The marker the drag grabbed: the one nearest the touched percent. When they sit together, picking the side the
    /// touch is on keeps both reachable (above grabs the limit, below grabs the resume point).
    public static func handle(at p: Int, upper: Int, lower: Int) -> Handle {
        let du = distance(p, upper), dl = distance(p, lower)
        if du == dl { return p > upper ? .upper : (p < lower ? .lower : .upper) }
        return du < dl ? .upper : .lower
    }

    /// Markers this close overlap under a pointer, so the drag direction picks one instead of the press point.
    public static let closeGap = 4

    /// Which marker a drag that started at `start` and is now at `now` moves. When the markers are close, dragging up
    /// (clockwise) takes the limit and dragging down takes the resume point; nil until the drag has moved a step.
    public static func handle(start: Int, now: Int, upper: Int, lower: Int) -> Handle? {
        guard distance(upper, lower) <= closeGap else { return handle(at: start, upper: upper, lower: lower) }
        if now == start { return nil }
        return now > start ? .upper : .lower
    }

    /// Distance around the ring, where 0% and 100% are the same spot.
    public static func distance(_ a: Int, _ b: Int) -> Int { let d = abs(a - b) % 100; return min(d, 100 - d) }

    /// New (upper, lower) after moving one marker to `p`. The other marker is pushed along so resume stays below the limit,
    /// like the zone editor's sliders.
    public static func move(_ h: Handle, to p: Int, upper: Int, lower: Int, gap: Int = 1) -> (upper: Int, lower: Int) {
        switch h {
        case .upper:
            let u = min(upperRange.upperBound, max(upperRange.lowerBound, p))
            return (u, min(lower, u - gap))
        case .lower:
            let l = min(lowerRange.upperBound, max(lowerRange.lowerBound, p))
            return (max(upper, l + gap), l)
        }
    }
}
