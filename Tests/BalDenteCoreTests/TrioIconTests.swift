import XCTest
@testable import BalDenteCore

final class TrioIconTests: XCTestCase {
    func testTopIndicator() {
        XCTAssertEqual(TrioRules.topIndicator(charging: true, plugged: true, showPercentage: true, showChargingIndicator: true, percentageWhenConnected: false), .bolt)
        XCTAssertEqual(TrioRules.topIndicator(charging: false, plugged: true, showPercentage: true, showChargingIndicator: true, percentageWhenConnected: false), .number)
        XCTAssertEqual(TrioRules.topIndicator(charging: false, plugged: true, showPercentage: true, showChargingIndicator: true, percentageWhenConnected: true), .number)
        XCTAssertEqual(TrioRules.topIndicator(charging: true, plugged: true, showPercentage: true, showChargingIndicator: false, percentageWhenConnected: false), .number)
        XCTAssertEqual(TrioRules.topIndicator(charging: false, plugged: false, showPercentage: false, showChargingIndicator: true, percentageWhenConnected: false), .none)
    }

    func testFullRingLevelScalesProgress() {
        XCTAssertEqual(TrioRules.ringProgress(percent: 80, full: 80), 1)
        XCTAssertEqual(TrioRules.ringProgress(percent: 40, full: 80), 0.5)
        XCTAssertEqual(TrioRules.ringProgress(percent: 95, full: 80), 1)
        XCTAssertEqual(TrioRules.ringProgress(percent: 50, full: 0), 0.5)   // a bad setting can't divide by zero
    }

    func testVolumeDotsAndWifiBars() {
        XCTAssertEqual(TrioRules.volumeDots(volume: 0.01, muted: false), 1)
        XCTAssertEqual(TrioRules.volumeDots(volume: 0.5, muted: false), 2)
        XCTAssertEqual(TrioRules.volumeDots(volume: 1, muted: false), 4)
        XCTAssertEqual(TrioRules.volumeDots(volume: 1, muted: true), 0)
        XCTAssertEqual(TrioRules.wifiBars(rssi: -50), 3)
        XCTAssertEqual(TrioRules.wifiBars(rssi: -80), 1)
        XCTAssertEqual(TrioRules.wifiBars(rssi: 0), 0)
    }

    func testGapMappingRoundTrips() {
        let gap = TrioGeometry.numberGap
        for p in [0.0, 0.1, 0.3, 0.7, 0.95, 1] where TrioGeometry.lastVisible(p, gap: gap) == p {
            XCTAssertEqual(TrioGeometry.progress(visible: TrioGeometry.visible(p, gap: gap), gap: gap), p, accuracy: 1e-9)
        }
        XCTAssertEqual(TrioGeometry.lastVisible(0.5, gap: gap), (1 - TrioGeometry.gapFraction(gap)) / 2, accuracy: 1e-9)
    }

    func testGapIsLeftEmpty() {
        // Nothing of a full ring may pass through the top of the gap, where the percentage sits.
        let path = TrioGeometry.arc(from: 0, to: 1, gap: TrioGeometry.numberGap)
        let stroked = path.copy(strokingWithWidth: 8, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        XCTAssertFalse(stroked.contains(CGPoint(x: TrioGeometry.centerX, y: TrioGeometry.ringCenter.y - TrioGeometry.ringRadius)))
        XCTAssertTrue(stroked.contains(TrioGeometry.point(at: 0.2)))
    }

    func testChargingFrameTravelsThenBeats() {
        let start = ChargingFrame.at(progress: 0.6, t: 0, cycle: 1.8, gap: 0, boltInGap: false)!
        XCTAssertEqual(start.head, 0, accuracy: 1e-9)
        let mid = ChargingFrame.at(progress: 0.6, t: 0.8, cycle: 1.8, gap: 0, boltInGap: false)!
        XCTAssertGreaterThan(mid.head, 0); XCTAssertLessThan(mid.head, 0.6)
        XCTAssertNotNil(mid.tail)
        let beat = ChargingFrame.at(progress: 0.6, t: 1.8 - 0.125, cycle: 1.8, gap: 0, boltInGap: false)!
        XCTAssertEqual(beat.head, 0.6, accuracy: 1e-9)
        XCTAssertGreaterThan(beat.heartbeatAlpha, 0.9)
        // Low charge: no tail, the bead alone.
        XCTAssertNil(ChargingFrame.at(progress: 0.1, t: 0.8, cycle: 1.8, gap: 0, boltInGap: false)!.tail)
    }

    func testBoltPulsesOnlyWhileHeadCrossesGap() {
        let gap = TrioGeometry.boltGap
        let scales = stride(from: 0.0, to: 1.55, by: 0.05).compactMap {
            ChargingFrame.at(progress: 1, t: $0, cycle: 1.8, gap: gap, boltInGap: true)?.boltScale
        }
        XCTAssertGreaterThan(scales.max()!, 1.1)
        XCTAssertEqual(scales.first!, 1)
        // A fill that stops before the gap never reaches the bolt.
        let low = stride(from: 0.0, to: 1.55, by: 0.05).compactMap {
            ChargingFrame.at(progress: 0.3, t: $0, cycle: 1.8, gap: gap, boltInGap: true)?.boltScale
        }
        XCTAssertEqual(low.max()!, 1)
    }
}
