import XCTest
@testable import BalDenteCore

final class CalibrationProgressTests: XCTestCase {
    private func task(_ phase: String, rest: Date? = nil) -> TaskState {
        var t = TaskState(); t.kind = "calibrate"; t.phase = phase; t.restUntil = rest; return t
    }

    func testPhases() {
        XCTAssertEqual(CalibrationProgress.text(task("discharge"), percent: 42), "Step 1 of 3: draining, 42% now (27% to go)")
        XCTAssertEqual(CalibrationProgress.text(task("discharge"), percent: 15), "Step 1 of 3: draining, 15% now")
        XCTAssertEqual(CalibrationProgress.text(task("charge"), percent: 60), "Step 2 of 3: charging, 60% now (40% to go)")
    }

    func testRestCountsDownAndRoundsUp() {
        let now = Date()
        XCTAssertEqual(CalibrationProgress.text(task("rest", rest: now.addingTimeInterval(34 * 60 - 10)), percent: 100, now: now), "Step 3 of 3: resting, 34 min left")
        XCTAssertEqual(CalibrationProgress.text(task("rest", rest: now.addingTimeInterval(-5)), percent: 100, now: now), "Step 3 of 3: resting, 1 min left")
        XCTAssertEqual(CalibrationProgress.text(task("rest"), percent: 100), "Step 3 of 3: resting at 100%")
    }

    func testOtherTasksHaveNoProgress() {
        var t = TaskState(); t.kind = "discharge"
        XCTAssertNil(CalibrationProgress.text(t, percent: 50))
    }
}

final class CalibrationFinishTests: XCTestCase {
    private func task(_ phase: String, rest: Date?) -> TaskState {
        var t = TaskState(); t.kind = "calibrate"; t.phase = phase; t.restUntil = rest; return t
    }

    func testFullCourseCountsAsFinished() {
        let now = Date()
        XCTAssertTrue(CalibrationProgress.finishedCleanly(task("rest", rest: now.addingTimeInterval(-20)), now: now))
        XCTAssertTrue(CalibrationProgress.finishedCleanly(task("rest", rest: now.addingTimeInterval(30)), now: now))   // refresh lag
    }

    func testCancelledEarlyDoesNot() {
        let now = Date()
        XCTAssertFalse(CalibrationProgress.finishedCleanly(task("rest", rest: now.addingTimeInterval(20 * 60)), now: now))
        XCTAssertFalse(CalibrationProgress.finishedCleanly(task("charge", rest: nil), now: now))
        XCTAssertFalse(CalibrationProgress.finishedCleanly(task("discharge", rest: nil), now: now))
    }

    func testWording() {
        XCTAssertEqual(ChangeEvent.calibrationEnded(completed: true).title, "Calibration complete")
        XCTAssertEqual(ChangeEvent.calibrationEnded(completed: false).title, "Calibration cancelled")
        XCTAssertEqual(ChangeEvent.calibrationEnded(completed: true).category, .manual)
        XCTAssertNil(CalibrationProgress.lastText(nil))
        XCTAssertNotNil(CalibrationProgress.lastText(Date()))
    }
}

final class CalibrationLogTests: XCTestCase {
    private let now = Date()
    private func ago(_ d: Int) -> Date { now.addingTimeInterval(-Double(d) * 86400) }

    func testReminderWaitsNinetyDays() {
        XCTAssertFalse(CalibrationReminder.due(last: ago(89), baseline: ago(200), lastReminded: nil, now: now))
        XCTAssertTrue(CalibrationReminder.due(last: ago(91), baseline: ago(200), lastReminded: nil, now: now))
    }

    func testNoRecordedCalibrationCountsFromFirstCheck() {
        XCTAssertFalse(CalibrationReminder.due(last: nil, baseline: ago(5), lastReminded: nil, now: now))
        XCTAssertTrue(CalibrationReminder.due(last: nil, baseline: ago(95), lastReminded: nil, now: now))
    }

    func testReminderRepeatsMonthlyNotDaily() {
        XCTAssertFalse(CalibrationReminder.due(last: ago(120), baseline: ago(300), lastReminded: ago(3), now: now))
        XCTAssertTrue(CalibrationReminder.due(last: ago(150), baseline: ago(300), lastReminded: ago(31), now: now))
    }

    func testNewCalibrationRestartsReminders() {
        XCTAssertFalse(CalibrationReminder.due(last: ago(2), baseline: ago(300), lastReminded: ago(40), now: now))
    }

    func testEntriesPairBeforeAndAfter() {
        let cal = Calendar.current
        let day = cal.startOfDay(for: now)
        func pt(_ d: Int, _ h: Int?) -> HistoryPoint { HistoryPoint(date: cal.date(byAdding: .day, value: d, to: day)!, health: h, cycles: nil, battery: nil) }
        let pts = [pt(-3, 93), pt(-1, 92), pt(0, 92), pt(1, 91)]
        let e = CalibrationHistory.entries(dates: [now], points: pts)
        XCTAssertEqual(e.first?.before, 92)
        XCTAssertEqual(e.first?.after, 91)
        XCTAssertNil(CalibrationHistory.entries(dates: [now], points: [pt(-1, 92)]).first?.after)
        XCTAssertTrue(CalibrationHistory.entries(dates: [], points: pts).isEmpty)
    }
}
