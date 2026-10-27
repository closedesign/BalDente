import XCTest
@testable import BalDenteCore

final class ChargerCutTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private let noon = Date(timeIntervalSince1970: 1_800_000_000)

    func testLoadGuardOnlyJustPastTheLimitAndOnlyWhenBusy() {
        func keep(_ pct: Int, load: Double = 6, on: Bool = true) -> Bool {
            LoadGuard.keepCharging(enabled: on, load1: load, cores: 8, percent: pct, upper: 80)
        }
        XCTAssertTrue(keep(80)); XCTAssertTrue(keep(81))
        XCTAssertFalse(keep(82), "two points over is where it always cuts")
        XCTAssertFalse(keep(79), "below the limit the normal logic decides")
        XCTAssertFalse(keep(80, load: 1), "an idle Mac cuts as usual")
        XCTAssertFalse(keep(80, on: false))
        XCTAssertFalse(LoadGuard.busy(load1: 5, cores: 0))
    }

    func testBatteryHoldCountsOnlyHeldSamples() {
        var h = BatteryHold()
        XCTAssertFalse(h.record(held: false, elapsed: 20, at: noon, calendar: cal))
        XCTAssertTrue(h.record(held: true, elapsed: 20, at: noon, calendar: cal))
        XCTAssertFalse(h.record(held: true, elapsed: 3600, at: noon, calendar: cal), "a sleep gap isn't counted")
        XCTAssertEqual(h.totalHours(now: noon, calendar: cal), 20.0 / 3600, accuracy: 1e-9)
    }

    func testBatteryHoldWeekIsSevenDaysOldestFirstAndPrunes() {
        var h = BatteryHold()
        h.record(held: true, elapsed: 60, at: noon.addingTimeInterval(-10 * 86_400), calendar: cal)
        h.record(held: true, elapsed: 60, at: noon, calendar: cal)
        let w = h.week(now: noon, calendar: cal)
        XCTAssertEqual(w.count, 7)
        XCTAssertEqual(w.last?.hours ?? 0, 60.0 / 3600, accuracy: 1e-9)
        XCTAssertEqual(h.days.count, 1, "the 10-day-old row is pruned")
    }

    func testOlderHelperStatusStillDecodes() throws {
        let s = Status(percent: 80, adapterOn: true, state: LimiterState(), backend: "adapter(CHIE)", chargeKeys: ["bfF0"])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        json.removeValue(forKey: "chargeKeys")
        var state = json["state"] as! [String: Any]; state.removeValue(forKey: "loadGuard"); json["state"] = state
        let old = try JSONDecoder().decode(Status.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.chargeKeys)
        XCTAssertTrue(old.state.loadGuard)
    }

    func testDiagnosticsAndEventWording() {
        let d = DiagnosticsInfo(appVersion: "1", macOS: "27", mac: "m", helper: "running", zoneCount: 1, chargeKeys: [])
        XCTAssertTrue(d.report.contains("Pass-through keys readable: none"))
        let e = ChangeEvent.chargeKeysOpened(["bfF0"])
        XCTAssertEqual(e.category, .system)
        XCTAssertTrue(e.body.contains("bfF0"))
    }
}
