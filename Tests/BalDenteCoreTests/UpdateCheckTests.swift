import XCTest
@testable import BalDenteCore

final class UpdateCheckTests: XCTestCase {
    func testPicksHighestNonDraft() {
        let json = """
        [{"tag_name":"v0.9","html_url":"https://x/9","draft":false},
         {"tag_name":"v0.10","html_url":"https://x/10","draft":false},
         {"tag_name":"v1.0","html_url":"https://x/11","draft":true}]
        """
        XCTAssertEqual(UpdateCheck.latest(from: Data(json.utf8))?.version, "0.10")
    }
    func testGarbageAndEmpty() {
        XCTAssertNil(UpdateCheck.latest(from: Data("{}".utf8)))
        XCTAssertNil(UpdateCheck.latest(from: Data("[]".utf8)))
    }
    func testNewer() {
        let r = UpdateCheck.Release(version: "0.7", page: URL(string: "https://x")!)
        XCTAssertTrue(UpdateCheck.isNewer(r, than: "0.6"))
        XCTAssertFalse(UpdateCheck.isNewer(r, than: "0.7"))
        XCTAssertFalse(UpdateCheck.isNewer(r, than: "dev"))
    }
    func testDue() {
        let now = Date()
        XCTAssertTrue(UpdateCheck.due(lastCheck: nil, now: now))
        XCTAssertFalse(UpdateCheck.due(lastCheck: now.addingTimeInterval(-3600), now: now))
        XCTAssertTrue(UpdateCheck.due(lastCheck: now.addingTimeInterval(-90000), now: now))
    }
    func testOldConfigKeepsValues() throws {
        let json = #"{"zones":[{"name":"Home","networks":["Wifi"],"upper":60,"lower":55}],"defaultUpper":70,"defaultLower":65}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(c.zones.first?.upper, 60); XCTAssertEqual(c.zones.first?.networks, ["Wifi"]); XCTAssertEqual(c.defaultUpper, 70)
    }
    func testOldScheduleKeepsValues() throws {
        let s = try JSONDecoder().decode(Schedule.self, from: Data(#"{"enabled":true,"hour":5}"#.utf8))
        XCTAssertTrue(s.enabled); XCTAssertEqual(s.hour, 5)
    }

    func testAllEntriesNewestFirst() {
        let md = "# Changelog\n\n## Road to 1.0\n- not a version\n\n## 0.9 (x)\n- a\n  more\n\n## 0.10\n- b\n\n## 0.8\n"
        let e = WhatsNew.allEntries(in: md)
        XCTAssertEqual(e.map(\.version), ["0.10", "0.9"])
        XCTAssertEqual(e[1].items, ["a more"])
    }
}
