import XCTest
@testable import BalDenteCore

final class ZoneWearTests: XCTestCase {
    var cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 12))! }

    func testCountsOnlyAboveThresholdAndShortSteps() {
        var w = ZoneWear()
        XCTAssertTrue(w.record(zone: "Home", percent: 90, elapsed: 20, at: now, calendar: cal))
        XCTAssertFalse(w.record(zone: "Home", percent: 80, elapsed: 20, at: now, calendar: cal))
        XCTAssertFalse(w.record(zone: "Home", percent: 95, elapsed: 3600, at: now, calendar: cal))   // a sleep gap
        XCTAssertFalse(w.record(zone: "Top Up", percent: 95, elapsed: 20, at: now, calendar: cal))
        XCTAssertEqual(w.weekly(now: now, calendar: cal).first?.hours ?? 0, 20.0 / 3600, accuracy: 1e-9)
    }

    func testOldDaysDropOut() {
        var w = ZoneWear()
        w.record(zone: "School", percent: 90, elapsed: 60, at: now.addingTimeInterval(-10 * 86400), calendar: cal)
        w.record(zone: "Home", percent: 90, elapsed: 60, at: now, calendar: cal)
        XCTAssertEqual(w.weekly(now: now, calendar: cal).map(\.zone), ["Home"])
    }

    func testSuggestion() {
        var w = ZoneWear()
        for d in 0..<4 { w.days[ZoneWear.dayKey(now.addingTimeInterval(-Double(d) * 86400), calendar: cal)] = ["Travel": 5 * 3600, "Home": 9 * 3600] }
        let config = Config()   // Home 50%, Travel 100%
        let s = WearSuggestion.suggest(w, config: config, now: now, calendar: cal)
        XCTAssertEqual(s?.zone, "Travel")
        XCTAssertEqual(s?.hours, 20)
        XCTAssertNil(WearSuggestion.suggest(w, config: config, dismissed: ["Travel"], now: now, calendar: cal), "Home is already under 80%")
    }

    func testNeedsSomeDays() {
        var w = ZoneWear()
        w.days[ZoneWear.dayKey(now, calendar: cal)] = ["Default": 20 * 3600]
        var config = Config(); config.defaultUpper = 90
        XCTAssertNil(WearSuggestion.suggest(w, config: config, now: now, calendar: cal))
    }
}
