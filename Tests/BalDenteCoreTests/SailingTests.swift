import XCTest
@testable import BalDenteCore

final class SailingTests: XCTestCase {
    func testOffByDefault() {
        XCTAssertNil(Config().sailing)
        XCTAssertNil(try JSONDecoder().decode(Config.self, from: Data("{}".utf8)).sailing)
    }

    func testSailingOffResumesOnePointBelowTheLimit() {
        let t = Target(label: "Home", upper: 50, lower: 45)
        XCTAssertEqual(t.sending(sailing: false).lower, 49)
        XCTAssertEqual(t.sending(sailing: false).upper, 50)
    }

    func testSailingOnKeepsTheSavedResumeLevel() {
        let t = Target(label: "Home", upper: 50, lower: 45)
        XCTAssertEqual(t.sending(sailing: true), t)
    }

    func testLowestLimitStaysAcceptedByTheHelper() {
        XCTAssertEqual(ResumeLevel.effective(upper: 5, lower: 1, sailing: false), 4)
        XCTAssertEqual(ResumeLevel.effective(upper: 1, lower: 1, sailing: false), 1)
    }

    func testZoneShowsTheEnforcedLevelButKeepsItsSavedOne() {
        let z = Zone(name: "School", upper: 80, lower: 75)
        XCTAssertEqual(z.showing(sailing: false).lower, 79)
        XCTAssertEqual(z.lower, 75)
    }
}
