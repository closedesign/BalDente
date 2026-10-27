import XCTest
@testable import BalDenteCore

final class PowerSourceTests: XCTestCase {
    private func make(battery: Bool = false, charging: Bool = false, charged: Bool = false, held: Bool = false, pct: Int = 80, upper: Int = 80) -> PowerSourceState {
        PowerSourceState(onBattery: battery, charging: charging, charged: charged, held: held, percent: pct, upper: upper)
    }

    func testUnpluggedIsBattery() {
        let s = make(battery: true)
        XCTAssertEqual(s.sourceName, "Battery")
        XCTAssertEqual(s.headline(upper: 80, percent: 80), "On battery")
    }

    func testChargingSaysChargingTo() {
        XCTAssertEqual(make(charging: true, pct: 60).headline(upper: 80, percent: 60), "Charging to 80%")
    }

    func testAtLimitNotChargingIsUsingACPower() {
        let s = make()   // e.g. macOS's own 80% Charge Limit
        XCTAssertEqual(s.sourceName, "Power Adapter")
        XCTAssertEqual(s.headline(upper: 80, percent: 80), "Using AC power")
        XCTAssertEqual(s.caption(compact: true).text, "AC power")
    }

    func testHeldByBalDente() {
        XCTAssertEqual(make(held: true, pct: 70).headline(upper: 80, percent: 70), "Holding at 70%")
    }

    func testFullAndCompactCaptions() {
        XCTAssertEqual(make(charged: true, pct: 100, upper: 100).headline(upper: 100, percent: 100), "Using AC power")
        XCTAssertEqual(make(battery: true).caption(compact: true).text, "Battery")
        XCTAssertEqual(make(battery: true).caption(compact: false).text, "On battery")
    }
}
