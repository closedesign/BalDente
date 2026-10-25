import XCTest
@testable import BalDenteCore

final class HistoryTests: XCTestCase {
    func testParseSkipsBadRowsAndTreatsZeroHealthAsUnknown() {
        let csv = "date,health_percent,cycles,battery_percent\n2026-10-02,0,200,70\nnonsense\n2026-10-01,93,199,80\n2026-10-03,92,,60\n"
        let p = HealthHistory.parse(csv)
        XCTAssertEqual(p.count, 3)
        XCTAssertEqual(p.map(\.health), [93, nil, 92])
        XCTAssertEqual(p.first?.cycles, 199)
        XCTAssertNil(p.last?.cycles)
    }

    func testDownsampleKeepsEnds() {
        let pts = (0..<1000).map { HistoryPoint(date: Date(timeIntervalSince1970: Double($0) * 86400), health: $0, cycles: nil, battery: nil) }
        let d = HealthHistory.downsample(pts, max: 50)
        XCTAssertEqual(d.count, 50)
        XCTAssertEqual(d.first?.health, 0); XCTAssertEqual(d.last?.health, 999)
        XCTAssertEqual(HealthHistory.downsample(Array(pts.prefix(10)), max: 50).count, 10)
    }

    func testPickSkipsEventsTooSoonToChargeFor() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let soon = now.addingTimeInterval(20 * 60), later = now.addingTimeInterval(3 * 3600)
        XCTAssertEqual(ReadyPlan.pick(starts: [later, soon], now: now, bufferMinutes: 30), later)
        XCTAssertNil(ReadyPlan.pick(starts: [soon], now: now, bufferMinutes: 30))
    }

    func testSpecSubtractsBuffer() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 9, minute: 0))!   // a Tuesday
        XCTAssertEqual(ReadyPlan.spec(eventStart: start, bufferMinutes: 30, calendar: cal), "3@08:30@100")
        let early = cal.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 0, minute: 10))!
        XCTAssertEqual(ReadyPlan.spec(eventStart: early, bufferMinutes: 30, calendar: cal), "2@23:40@100")   // rolls back to Monday
    }
}
final class HistorySummaryTests: XCTestCase {
    func testDuplicateDaysCollapseAndSummaryUsesHealthDates() {
        let csv = "date,health_percent,cycles,battery_percent\n2026-10-20,,198,50\n2026-10-24,92,200,71\n2026-10-25,92,200,76\n2026-10-25,93,200,79\n"
        let pts = HealthHistory.parse(csv)
        XCTAssertEqual(pts.count, 3)
        let s = HealthHistory.summary(pts)
        XCTAssertEqual(s.healthNow, 93)
        XCTAssertEqual(s.healthDelta, 1)
        XCTAssertEqual(s.healthDays, 1)
        XCTAssertEqual(s.cyclesAdded, 2)
    }
}

final class HealthProjectionTests: XCTestCase {
    private func series(_ vals: [Int], step: Int) -> [(Date, Int)] {
        vals.enumerated().map { (Date(timeIntervalSince1970: Double($0.offset * step) * 86400), $0.element) }
    }
    func testSteadyDeclineProjects() {
        // -1 point per 10 days, now 95 -> 80 in ~150 days
        let d = HealthHistory.daysToReach(80, series([98, 97, 96, 95], step: 10))
        XCTAssertEqual(d, 150)
    }
    func testNeedsTrendAndSpan() {
        XCTAssertNil(HealthHistory.daysToReach(80, series([95, 95, 95, 95], step: 10)))
        XCTAssertNil(HealthHistory.daysToReach(80, series([97, 96, 95], step: 2)))
        XCTAssertEqual(HealthHistory.daysToReach(80, series([82, 81, 80], step: 10)), 0)
    }
}
