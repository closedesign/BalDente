import XCTest
@testable import BalDenteCore

final class MacChargeLimitTests: XCTestCase {
    func testRoles() {
        XCTAssertEqual(MacChargeLimit.role(upper: 80, macLimit: 80), .macOSHolds)
        XCTAssertEqual(MacChargeLimit.role(upper: 90, macLimit: 90), .macOSHolds)
        XCTAssertEqual(MacChargeLimit.role(upper: 100, macLimit: 80), .blocked)
        XCTAssertEqual(MacChargeLimit.role(upper: 85, macLimit: 80), .blocked)
        XCTAssertEqual(MacChargeLimit.role(upper: 60, macLimit: 80), .appHolds, "below macOS's minimum BalDente must cut the charger")
        XCTAssertEqual(MacChargeLimit.role(upper: 80, macLimit: nil), .appHolds)
        XCTAssertEqual(MacChargeLimit.role(upper: 80, macLimit: 77), .appHolds, "a value that isn't a macOS step is ignored")
    }

    func testMatchingZoneIsSentAsNoLimit() {
        let t = Target(label: "School", upper: 80, lower: 75, zoneID: UUID())
        let s = MacChargeLimit.sending(t, macLimit: 80)
        XCTAssertEqual(s.upper, 100); XCTAssertEqual(s.lower, 99)
        XCTAssertEqual(s.label, "School"); XCTAssertEqual(s.zoneID, t.zoneID)
        XCTAssertEqual(MacChargeLimit.sending(t, macLimit: 85), t, "a lower zone stays with BalDente")
        XCTAssertEqual(MacChargeLimit.sending(t, macLimit: nil), t)
    }

    func testNeededSetting() {
        XCTAssertEqual(MacChargeLimit.neededSetting(for: 82), 85)
        XCTAssertEqual(MacChargeLimit.neededSetting(for: 95), 95)
        XCTAssertEqual(MacChargeLimit.neededSetting(for: 100), 100)
    }

    func testReminderWording() {
        let on = ChangeEvent.macLimit(blocked: true, zone: "Travel", upper: 100, macLimit: 80)
        XCTAssertEqual(on.category, .system)
        XCTAssertTrue(on.body.contains("100%")); XCTAssertTrue(on.body.contains("System Settings"))
        XCTAssertTrue(ChangeEvent.macLimit(blocked: false, zone: "School", upper: 80, macLimit: 80).body.contains("back to 80%"))
    }

    func testFreshInstallDefaultsAndOldConfigs() throws {
        XCTAssertEqual(Config().zones.map(\.upper), [80, 80, 100])
        XCTAssertNil(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).macLimit)
    }
}
