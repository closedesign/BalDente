import XCTest
@testable import BalDenteCore

final class AdvisorTests: XCTestCase {
    let mac = MacProfile(productName: "MacBook Air", modelID: "Mac15,12", appleSilicon: true)

    func testCycleBudgetAndPace() {
        XCTAssertEqual(BatteryAdvisor.monthsToRating(cycles: 400, rated: 1000, cyclesPerMonth: 20)!, 30, accuracy: 0.01)
        XCTAssertNil(BatteryAdvisor.monthsToRating(cycles: 400, rated: 1000, cyclesPerMonth: nil))
        let d0 = Date(timeIntervalSince1970: 0)
        let pts = [HistoryPoint(date: d0, health: 99, cycles: 100, battery: 50),
                   HistoryPoint(date: d0.addingTimeInterval(60 * 86400), health: 98, cycles: 130, battery: 50)]
        XCTAssertEqual(BatteryAdvisor.cyclesPerMonth(pts)!, 15, accuracy: 0.01)
        XCTAssertNil(BatteryAdvisor.cyclesPerMonth(Array(pts.prefix(1))))
    }

    func testTips() {
        let t = BatteryAdvisor.tips(profile: mac, cycles: 120, health: 82, tempC: 38, upperLimit: 100, cyclesPerMonth: nil)
        XCTAssertTrue(t.contains { $0.id == "wear" && $0.level == .warn })
        XCTAssertTrue(t.contains { $0.id == "heat" })
        XCTAssertTrue(t.contains { $0.id == "limit" })
        let ok = BatteryAdvisor.tips(profile: mac, cycles: 300, health: 94, tempC: 30, upperLimit: 80, cyclesPerMonth: nil)
        XCTAssertTrue(ok.contains { $0.id == "health" && $0.level == .good })
        XCTAssertFalse(ok.contains { $0.id == "heat" || $0.id == "limit" })
        let old = BatteryAdvisor.tips(profile: mac, cycles: 900, health: 78, tempC: nil, upperLimit: 80, cyclesPerMonth: nil)
        XCTAssertTrue(old.contains { $0.title == "Below Apple's design point" })
    }

    func testSanitizedConfig() {
        var c = Config()
        c.zones = [Zone(name: "A", upper: 150, lower: 200), Zone(name: "a", upper: 50, lower: 50)]
        c.overrideZone = "gone"
        let s = c.sanitized()
        XCTAssertEqual(s.zones[0].upper, 100); XCTAssertEqual(s.zones[0].lower, 99)
        XCTAssertEqual(s.zones[1].lower, 49)
        XCTAssertNotEqual(s.zones[0].name.lowercased(), s.zones[1].name.lowercased())
        XCTAssertNil(s.overrideZone)
    }

    func testUpcomingMarksTooSoon() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let u = ReadyPlan.upcoming(starts: [now.addingTimeInterval(1200), now.addingTimeInterval(7200), now.addingTimeInterval(-60)], now: now, bufferMinutes: 30)
        XCTAssertEqual(u.count, 2); XCTAssertFalse(u[0].chargeable); XCTAssertTrue(u[1].chargeable)
    }

    func testShortMonthScheduleFiresOnLastDay() {
        XCTAssertTrue(scheduleDayMatches(days: [31], today: 30, daysInMonth: 30))
        XCTAssertTrue(scheduleDayMatches(days: [30], today: 28, daysInMonth: 28))
        XCTAssertFalse(scheduleDayMatches(days: [31], today: 29, daysInMonth: 30))
        XCTAssertTrue(scheduleDayMatches(days: [15], today: 15, daysInMonth: 31))
    }
}
