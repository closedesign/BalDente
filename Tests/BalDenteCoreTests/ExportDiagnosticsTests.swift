import XCTest
@testable import BalDenteCore

final class ExportDiagnosticsTests: XCTestCase {
    func testAutoDischargeSurvivesSaveAndLoad() throws {
        var c = Config(); c.autoDischarge = true
        let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.autoDischarge, true)
    }
    func testExportRoundTripAndSanitizing() throws {
        var c = Config(); c.zones[0].upper = 500; c.zones[1].name = "Home"; c.overrideZone = "Home"
        let back = try SettingsExport.decode(SettingsExport.encode(c, version: "1.0"))
        XCTAssertEqual(back.zones[0].upper, 100)
        XCTAssertEqual(back.zones[1].name, "Home 2")
        XCTAssertNil(back.overrideZone)
    }
    func testBareConfigAndGarbage() throws {
        XCTAssertNoThrow(try SettingsExport.decode(JSONEncoder().encode(Config())))
        XCTAssertThrowsError(try SettingsExport.decode(Data("{\"hello\":1}".utf8)))
        XCTAssertThrowsError(try SettingsExport.decode(Data("nope".utf8)))
    }
    func testDiagnosticsLeavesOutNetworks() {
        let r = DiagnosticsInfo(appVersion: "v1.0 (3)", macOS: "15.0", mac: "MacBook Pro", helper: "running", backend: "CHIE",
                                percent: 80, tempC: 33.2, limit: "80% / 75% (Home)", zoneCount: 3, recent: ["Limit 80%"]).report
        XCTAssertTrue(r.contains("Helper: running"))
        XCTAssertTrue(r.contains("Battery: 80%, 33.2 °C"))
        XCTAssertTrue(r.contains("  - Limit 80%"))
    }
}
