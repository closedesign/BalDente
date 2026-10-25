import CoreGraphics
import Foundation

// The combined "trio" status icon: battery arc on top, network in the middle, volume at the bottom.
// Layout follows Status Trio's published artwork (status-menubar.svg, Apache-2.0, © lingyired):
// a 120-unit canvas, y pointing down, every element centered on x = 59.5.

public enum TrioGeometry {
    public static let side: CGFloat = 120
    public static let centerX: CGFloat = 59.5
    public static let ringCenter = CGPoint(x: centerX, y: 61.487)
    public static let ringRadius: CGFloat = 51.5
    /// The arc starts lower left, runs over the top and ends lower right, leaving the bottom open for volume.
    public static let ringStart: CGFloat = 148.69 * .pi / 180
    public static let ringSweep: CGFloat = 242.62 * .pi / 180
    public static let numberGap: CGFloat = 64
    public static let boltGap: CGFloat = 50

    /// Fraction of the arc hidden by a top gap of this width (arc length units).
    public static func gapFraction(_ width: CGFloat) -> Double {
        width > 0 ? min(1, Double(width / (ringRadius * ringSweep))) : 0
    }

    public static func point(at progress: Double) -> CGPoint {
        let a = ringStart + ringSweep * CGFloat(min(1, max(0, progress)))
        return CGPoint(x: ringCenter.x + ringRadius * cos(a), y: ringCenter.y + ringRadius * sin(a))
    }

    /// The part of the ring between two progress values, minus whatever falls inside the top gap.
    public static func arc(from start: Double, to end: Double, gap: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let s = min(1, max(0, start)), e = min(1, max(0, end))
        guard e > s else { return path }
        let g = gapFraction(gap)
        let pieces: [(Double, Double)] = g > 0 ? [(s, min(e, (1 - g) / 2)), (max(s, (1 + g) / 2), e)] : [(s, e)]
        for (a, b) in pieces where b > a {
            // Each piece is its own subpath; otherwise addArc joins them with a straight line across the gap.
            path.move(to: point(at: a))
            path.addArc(center: ringCenter, radius: ringRadius, startAngle: ringStart + ringSweep * CGFloat(a),
                        endAngle: ringStart + ringSweep * CGFloat(b), clockwise: false)
        }
        return path
    }

    /// Where a progress value lands along the visible (gap-free) arc, 0...1 of the visible length.
    public static func visible(_ progress: Double, gap: CGFloat) -> Double {
        let p = min(1, max(0, progress)), g = gapFraction(gap)
        let gs = (1 - g) / 2
        return p <= gs ? p : p >= gs + g ? p - g : gs
    }

    /// Inverse of `visible`.
    public static func progress(visible v: Double, gap: CGFloat) -> Double {
        let g = gapFraction(gap)
        let c = min(1 - g, max(0, v))
        return c <= (1 - g) / 2 ? c : c + g
    }

    /// The last point of `progress` that is actually drawn: a fill ending inside the gap stops at the gap's left edge.
    public static func lastVisible(_ progress: Double, gap: CGFloat) -> Double {
        let p = min(1, max(0, progress)), g = gapFraction(gap)
        let gs = (1 - g) / 2
        return p > gs && p < gs + g ? gs : p
    }

    // Four volume dots along the open bottom, left to right.
    public static let volumeDots = [CGPoint(x: 33, y: 104.2), CGPoint(x: 50.5, y: 111.2), CGPoint(x: 68.5, y: 111.7), CGPoint(x: 86, y: 105.8)]
    public static let volumeDotRadius: CGFloat = 5.5
    public static let volumeArcStart: CGFloat = 121.82 * .pi / 180
    public static let volumeArcEnd: CGFloat = 59.12 * .pi / 180
}

/// One frame of the charging highlight: a comet runs from the start of the ring to the charge level,
/// then a heartbeat ring blooms at the end. Passing the bolt in the top gap makes the bolt pulse.
public struct ChargingFrame: Equatable {
    public var tail: ClosedRange<Double>?
    public var head: Double
    public var headVisible: Bool
    public var beadAlpha: Double
    public var heartbeatAlpha: Double
    public var heartbeatScale: Double
    public var boltScale: Double
    public var boltTint: Double
    /// 0..<1 position of the wave rippling along the filled arc; loops seamlessly each cycle.
    public var wavePhase: Double = 0

    public static let steadyCycle: TimeInterval = 1.8
    public static let plugInBurst: TimeInterval = 0.6
    public static let levelUpBurst: TimeInterval = 0.3
    public static let heartbeat: TimeInterval = 0.25
    public static let fps = 20.0

    /// - Parameters:
    ///   - progress: charge level on the ring, 0...1.
    ///   - t: seconds into the current cycle.
    ///   - cycle: cycle length (steady 1.8 s; shorter bursts after plugging in or gaining a percent).
    ///   - gap: width of the top gap, 0 for none.
    ///   - boltInGap: whether the gap holds the bolt (so it can pulse).
    public static func at(progress: Double, t: TimeInterval, cycle: TimeInterval, gap: CGFloat, boltInGap: Bool) -> ChargingFrame? {
        guard progress.isFinite, t.isFinite, cycle > heartbeat else { return nil }
        let p = min(1, max(0, progress))
        let local = t.truncatingRemainder(dividingBy: cycle)
        let travel = cycle - heartbeat
        let end = TrioGeometry.lastVisible(p, gap: gap)
        let moving = local < travel
        // Ease out so the head arrives softly, like a fluid filling up.
        let x = min(1, local / travel)
        let head = end * (moving ? 1 - pow(1 - x, 2.2) : 1)
        let beat = moving ? 0 : min(1, (local - travel) / heartbeat)
        let pulse = beat > 0 && beat < 1 ? sin(.pi * beat) : 0

        let visibleLength = TrioGeometry.visible(1, gap: gap)
        let visibleFill = TrioGeometry.visible(p, gap: gap)
        let tailLength = min(0.32 * visibleLength, 0.78 * visibleFill)
        var tail: ClosedRange<Double>?
        if visibleFill >= 0.25 * visibleLength, head > 0, tailLength > 0 {
            let vh = TrioGeometry.visible(head, gap: gap)
            tail = TrioGeometry.progress(visible: max(0, vh - tailLength), gap: gap)...TrioGeometry.progress(visible: vh, gap: gap)
        }

        var boltScale = 1.0, boltTint = 0.0
        let g = TrioGeometry.gapFraction(gap), gs = (1 - g) / 2, ge = gs + g
        if boltInGap, g > 0, p >= ge, moving {
            // The head is hidden while it crosses the gap; map that crossing onto the bolt instead.
            let raw = p * (1 - pow(1 - x, 2.2))
            if raw > gs && raw < ge {
                let u = sin(.pi * (raw - gs) / g)
                boltScale = 1 + 0.2 * u; boltTint = u
            }
        }
        let headVisible = abs(TrioGeometry.lastVisible(head, gap: gap) - head) < 1e-9
        return ChargingFrame(tail: tail, head: head, headVisible: headVisible,
                             beadAlpha: headVisible ? (moving ? 1 : 1 - beat) : 0,
                             heartbeatAlpha: pulse, heartbeatScale: moving ? 1 : 1 + 0.55 * (1 - pulse),
                             boltScale: boltScale, boltTint: boltTint,
                             wavePhase: local / cycle)
    }
}

/// What sits in the battery arc's top gap.
public enum TopIndicator: Equatable { case none, number, bolt, plug }

public enum TrioRules {
    /// Mirrors Status Trio's battery display options.
    public static func topIndicator(charging: Bool, plugged: Bool, showPercentage: Bool,
                                    showChargingIndicator: Bool, percentageWhenConnected: Bool) -> TopIndicator {
        if showChargingIndicator {
            if charging { return .bolt }
            // Plugged in but not charging (held at the limit): show the number rather than a plug symbol.
            if plugged { return showPercentage ? .number : .none }
        }
        return showPercentage ? .number : .none
    }

    /// Text beside the menu bar icon, with a leading space (empty for none): the percentage while the ring shows a
    /// bolt or plug instead of it, then the time to full or empty.
    public static func sideText(present: Bool, percent: Int, plugged: Bool, charging: Bool,
                                minutesToFull: Int?, minutesToEmpty: Int?, top: TopIndicator,
                                showPercentWhileCharging: Bool, showPercentage: Bool, percentInMiddle: Bool,
                                showTime: Bool) -> String {
        guard present else { return "" }
        var parts: [String] = []
        if showPercentWhileCharging, showPercentage, !percentInMiddle, plugged || charging, top != .number {
            parts.append("\(percent)%")
        }
        if showTime, let m = charging ? minutesToFull : plugged ? nil : minutesToEmpty, m > 0 {
            parts.append(m >= 60 ? "\(m / 60):" + String(format: "%02d", m % 60) : "\(m)m")
        }
        return parts.isEmpty ? "" : " " + parts.joined(separator: " · ")
    }

    /// Ring fill, 0...1. `full` is the level that counts as a full ring, e.g. an 80% charge limit.
    public static func ringProgress(percent: Int, full: Int) -> Double {
        let f = (1...100).contains(full) ? full : 100
        return min(1, max(0, Double(percent) / Double(f)))
    }

    /// Wi-Fi bars from RSSI, matching the three steps macOS uses.
    public static func wifiBars(rssi: Int) -> Int {
        rssi == 0 ? 0 : rssi >= -60 ? 3 : rssi >= -72 ? 2 : 1
    }

    /// Lit volume dots out of four. Any audible level lights at least one.
    public static func volumeDots(volume: Double, muted: Bool) -> Int {
        muted || volume <= 0 ? 0 : min(4, max(1, Int((volume * 4).rounded(.up))))
    }
}
