import XCTest
@testable import BalDenteCore

final class HeatLimitTests: XCTestCase {
    func testClampStaysInDaemonRange() {
        XCTAssertEqual(HeatLimit.clamp(10), 30)
        XCTAssertEqual(HeatLimit.clamp(41), 41)
        XCTAssertEqual(HeatLimit.clamp(80), 60)
    }

    func testParseAcceptsUnitsAndClamps() {
        XCTAssertEqual(HeatLimit.parse("42"), 42)
        XCTAssertEqual(HeatLimit.parse(" 42 °C"), 42)
        XCTAssertEqual(HeatLimit.parse("99"), 60)
        XCTAssertEqual(HeatLimit.parse("5"), 30)
    }

    func testParseRejectsNonsense() {
        XCTAssertNil(HeatLimit.parse(""))
        XCTAssertNil(HeatLimit.parse("°C"))
        XCTAssertNil(HeatLimit.parse("12345"))
    }

    func testPresetsAreValid() {
        XCTAssertTrue(HeatLimit.presets.allSatisfy { HeatLimit.range.contains($0) })
        XCTAssertEqual(HeatLimit.fraction(30), 0)
        XCTAssertEqual(HeatLimit.fraction(60), 1)
    }
}

final class HeatLimitEntryTests: XCTestCase {
    func testTwoDigitsFinishTheEntry() {
        var e = HeatLimitEntry()
        XCTAssertNil(e.add("5"))
        XCTAssertEqual(e.pending, "5")
        XCTAssertEqual(e.add("5"), 55)
        XCTAssertEqual(e.pending, "")
    }

    func testReturnAcceptsOneDigitAndClamps() {
        var e = HeatLimitEntry()
        _ = e.add("4")
        XCTAssertEqual(e.commit(), 30)
        XCTAssertNil(e.commit())
    }

    func testBackspaceAndOutOfRange() {
        var e = HeatLimitEntry()
        _ = e.add("9"); e.backspace()
        XCTAssertEqual(e.pending, "")
        _ = e.add("9")
        XCTAssertEqual(e.add("9"), 60)
        XCTAssertNil(e.add("x"))
    }

    func testRangeAndDefault() {
        XCTAssertGreaterThan(HeatLimit.range.upperBound, 50)
        XCTAssertTrue(HeatLimit.range.contains(HeatLimit.defaultLimit))
        XCTAssertEqual(LimiterState().heatLimit, HeatLimit.defaultLimit)
    }

    func testWavePhaseLoopsWithinCycle() {
        let f = ChargingFrame.at(progress: 0.6, t: 0.9, cycle: 1.8, gap: 0, boltInGap: false)
        XCTAssertEqual(f?.wavePhase ?? -1, 0.5, accuracy: 1e-9)
    }
}

final class SideTextTests: XCTestCase {
    private func text(charging: Bool = true, plugged: Bool = true, top: TopIndicator = .bolt, toFull: Int? = 75,
                      percentWhileCharging: Bool = true, time: Bool = true) -> String {
        TrioRules.sideText(present: true, percent: 58, plugged: plugged, charging: charging, minutesToFull: toFull, minutesToEmpty: 200,
                           top: top, showPercentWhileCharging: percentWhileCharging, showPercentage: true, percentInMiddle: false, showTime: time)
    }

    func testChargingShowsPercentAndTime() { XCTAssertEqual(text(), " 58% · 1:15") }
    func testNumberAlreadyInRingIsNotRepeated() { XCTAssertEqual(text(top: .number), " 1:15") }
    func testPluggedButHeldShowsPercentOnly() { XCTAssertEqual(text(charging: false, toFull: nil), " 58%") }
    func testOnBatteryShowsTimeToEmpty() { XCTAssertEqual(text(charging: false, plugged: false, top: .number), " 3:20") }
    func testOptionsOff() { XCTAssertEqual(text(percentWhileCharging: false, time: false), "") }
    func testShortMinutes() { XCTAssertEqual(text(toFull: 9, percentWhileCharging: false), " 9m") }
}
