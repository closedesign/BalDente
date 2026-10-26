import XCTest
@testable import BalDenteCore

final class DecodingTests: XCTestCase {
    func testAutoDischargeSurvivesSaveAndLoad() throws {
        var c = Config()
        c.autoDischarge = true
        let back = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(back.autoDischarge, true)
        XCTAssertEqual(back, c)
    }

    func testOlderConfigWithoutAutoDischargeStillDecodes() throws {
        let c = try JSONDecoder().decode(Config.self, from: Data(#"{"defaultUpper": 70, "defaultLower": 60}"#.utf8))
        XCTAssertNil(c.autoDischarge)
        XCTAssertEqual(c.defaultUpper, 70)
    }

    func testStatusFromAnOlderHelperDecodes() throws {
        // No heatHold, tempC or ledAvailable: an older helper must not read as offline.
        let json = #"{"percent": 64, "adapterOn": true, "state": {}, "backend": "CHIE"}"#
        let s = try JSONDecoder().decode(Status.self, from: Data(json.utf8))
        XCTAssertEqual(s.percent, 64)
        XCTAssertFalse(s.heatHold)
        XCTAssertNil(s.ledAvailable)
    }

    func testStatusRoundTrips() throws {
        let s = Status(percent: 80, adapterOn: false, state: LimiterState(), backend: "CHIE", tempC: 31.5, heatHold: true, ledAvailable: true)
        let back = try JSONDecoder().decode(Status.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.heatHold, true)
        XCTAssertEqual(back.tempC, 31.5)
        XCTAssertEqual(back.ledAvailable, true)
    }
}
