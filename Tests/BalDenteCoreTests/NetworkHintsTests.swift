import XCTest
@testable import BalDenteCore

final class NetworkHintsTests: XCTestCase {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.locale = Locale(identifier: "en_US"); return c
    }()
    private func day(_ d: Int, _ h: Int = 10) -> Date { cal.date(from: DateComponents(year: 2026, month: 9, day: d, hour: h))! }   // Sep 1 2026 = Tuesday

    private func log(_ days: [Int], network: String = "CafeNet") -> NetworkLog {
        var l = NetworkLog()
        for d in days { l.record(network, at: day(d), calendar: cal) }
        return l
    }

    func testSuggestsARegularUnknownNetwork() throws {
        let s = try XCTUnwrap(NetworkHints.suggest(log([1, 3, 8, 10]), config: Config()))   // Tue, Thu, Tue, Thu
        XCTAssertEqual(s.network, "CafeNet")
        XCTAssertEqual(s.days, 4)
        XCTAssertEqual(s.weekdays, [3, 5])
        XCTAssertEqual(s.question(calendar: cal), "You're on “CafeNet” most Tue, Thu. Add it to a zone so its limit switches automatically?")
    }

    func testNeedsEnoughDaysSpreadOut() {
        XCTAssertNil(NetworkHints.suggest(log([1, 3, 8]), config: Config()))          // only 3 days
        XCTAssertNil(NetworkHints.suggest(log([1, 2, 3, 4]), config: Config()))       // a 4-day trip, not a routine
    }

    func testOneSightingPerDayAndPruning() {
        var l = NetworkLog()
        l.record("CafeNet", at: day(1, 9), calendar: cal); l.record("cafenet", at: day(1, 15), calendar: cal)
        XCTAssertEqual(l.sightings.count, 1)
        l.record("Other", at: day(30), calendar: cal)
        XCTAssertEqual(l.sightings.map(\.network), ["Other"])                         // Sep 1 is more than 28 days before Sep 30
    }

    func testKnownOrDismissedNetworksAreSkipped() {
        var c = Config(); c.zones[1].networks = ["cafenet"]
        XCTAssertNil(NetworkHints.suggest(log([1, 3, 8, 10]), config: c))
        XCTAssertNil(NetworkHints.suggest(log([1, 3, 8, 10]), config: Config(), dismissed: ["cafenet"]))
    }

    func testPicksTheMostFrequent() {
        var l = log([1, 3, 8, 10])
        for d in [1, 2, 3, 4, 8, 9] { l.record("Office", at: day(d), calendar: cal) }
        XCTAssertEqual(NetworkHints.suggest(l, config: Config())?.network, "Office")
    }

    func testWifiNameSkipsRouterAndBSSID() {
        XCTAssertEqual(NetworkHints.wifiName(["HomeNet", "aa:bb:cc:dd:ee:ff", "gw:11:22:33:44:55:66"]), "HomeNet")
        XCTAssertNil(NetworkHints.wifiName(["a0:b1:c2:d3:e4:f5", "gw:11:22:33:44:55:66"]))
        XCTAssertNil(NetworkHints.wifiName([]))
        XCTAssertEqual(NetworkHints.wifiName(["Cafe: Free"]), "Cafe: Free")
    }
}
