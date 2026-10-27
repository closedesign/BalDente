import XCTest
@testable import BalDenteCore

final class CalibrationRunTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testFullCourse() {
        var t = CalibrationRun.start(now: t0)
        var r = CalibrationRun.advance(t, percent: 60, now: t0)
        XCTAssertEqual(r.adapterOn, false); XCTAssertEqual(r.task.phase, "discharge")
        r = CalibrationRun.advance(r.task, percent: 15, now: t0 + 3600)
        XCTAssertEqual(r.task.phase, "charge"); XCTAssertEqual(r.adapterOn, true)
        r = CalibrationRun.advance(r.task, percent: 100, now: t0 + 7200)
        XCTAssertEqual(r.task.phase, "rest"); XCTAssertEqual(r.task.restUntil, t0 + 7200 + 3600)
        t = r.task
        r = CalibrationRun.advance(t, percent: 100, now: t0 + 7200 + 1800)
        XCTAssertEqual(r.outcome, .running)
        r = CalibrationRun.advance(t, percent: 100, now: t0 + 7200 + 3600)
        XCTAssertEqual(r.outcome, .finished); XCTAssertFalse(r.task.active); XCTAssertNil(r.adapterOn)
        XCTAssertTrue(CalibrationProgress.finishedCleanly(t, now: t0 + 7200 + 3600))
    }

    func testChargeThatStallsBelow100StillFinishes() {
        var t = CalibrationRun.start(now: t0); t.phase = "charge"; t.phaseStarted = t0
        XCTAssertEqual(CalibrationRun.advance(t, percent: 99, now: t0 + 3600).task.phase, "charge")
        XCTAssertEqual(CalibrationRun.advance(t, percent: 99, now: t0 + CalibrationRun.chargeStallLimit).task.phase, "rest")
        XCTAssertEqual(CalibrationRun.advance(t, percent: 90, now: t0 + CalibrationRun.chargeStallLimit).task.phase, "charge")   // still really charging
    }

    func testGivesUpAfterMaxDuration() {
        var t = CalibrationRun.start(now: t0); t.phase = "charge"
        let r = CalibrationRun.advance(t, percent: 40, now: t0 + CalibrationRun.maxDuration)
        XCTAssertEqual(r.outcome, .timedOut); XCTAssertFalse(r.task.active); XCTAssertNil(r.adapterOn)
        XCTAssertTrue(CalibrationProgress.timedOut(t, now: t0 + CalibrationRun.maxDuration))
        XCTAssertFalse(CalibrationProgress.timedOut(t, now: t0 + 3600))   // cancelled early
    }

    func testOldTaskWithoutTimestampsStartsTheClock() {
        var old = TaskState(); old.kind = "calibrate"; old.phase = "discharge"
        let r = CalibrationRun.advance(old, percent: 40, now: t0)
        XCTAssertEqual(r.outcome, .running); XCTAssertEqual(r.task.started, t0); XCTAssertEqual(r.adapterOn, false)
        var rest = old; rest.phase = "rest"   // a rest without a deadline gets one instead of resting forever
        XCTAssertEqual(CalibrationRun.advance(rest, percent: 100, now: t0).task.restUntil, t0 + CalibrationRun.restLength)
    }

    func testRanRecently() {
        XCTAssertFalse(CalibrationRun.ranRecently(nil, now: t0))
        XCTAssertTrue(CalibrationRun.ranRecently(t0 - 2 * 3600, now: t0))      // finished at 1 AM, a 3 AM plan is skipped
        XCTAssertFalse(CalibrationRun.ranRecently(t0 - 21 * 3600, now: t0))
        XCTAssertFalse(CalibrationRun.ranRecently(t0 + 3600, now: t0))         // clock moved back: don't block forever
    }

    func testElapsedText() {
        let t = CalibrationRun.start(now: t0)
        XCTAssertEqual(CalibrationProgress.elapsedText(t, now: t0 + 200 * 60), "Running 3 h 20 min. Stops on its own after 20 more h if it can't finish.")
        XCTAssertEqual(CalibrationProgress.elapsedText(t, now: t0 + 45 * 60), "Running 45 min. Stops on its own after 23 more h if it can't finish.")
        var old = TaskState(); old.kind = "calibrate"
        XCTAssertNil(CalibrationProgress.elapsedText(old, now: t0))
    }

    func testOldStateDecodes() throws {
        let json = #"{"kind":"calibrate","phase":"discharge","target":0}"#
        let t = try JSONDecoder().decode(TaskState.self, from: Data(json.utf8))
        XCTAssertNil(t.started); XCTAssertEqual(t.phase, "discharge")
        XCTAssertNil(try JSONDecoder().decode(LimiterState.self, from: Data("{}".utf8)).lastCalibrated)
    }

    func testTimedOutWording() {
        XCTAssertEqual(ChangeEvent.calibrationEnded(completed: false, timedOut: true).title, "Calibration stopped")
    }

    func testPauseHandsBackToLimiterAndStopsTheClock() {
        var t = CalibrationRun.start(now: t0); t.phase = "rest"; t.restUntil = t0 + 3600
        let paused = CalibrationRun.pause(t, now: t0 + 600)
        let r = CalibrationRun.advance(paused, percent: 100, now: t0 + CalibrationRun.maxDuration + 10)
        XCTAssertEqual(r.outcome, .running); XCTAssertNil(r.adapterOn); XCTAssertEqual(r.task, paused)   // no timeout while paused
        let back = CalibrationRun.resume(paused, now: t0 + 600 + 7200)
        XCTAssertNil(back.pausedAt)
        XCTAssertEqual(back.restUntil, t0 + 3600 + 7200); XCTAssertEqual(back.started, t0 + 7200)
        XCTAssertEqual(CalibrationRun.pause(paused, now: t0 + 9999), paused)   // pausing twice keeps the first time
        XCTAssertEqual(CalibrationProgress.text(paused, percent: 100), "Paused at step 3 of 3 (resting)")
    }

    func testDrainEstimate() {
        // 5747 mAh at 11.4 V is about 65.5 Wh; 85% of that at 14 W is about 4 h.
        let h = CalibrationPlan.drainHours(percent: 100, maxMAh: 5747, volts: 11.4, watts: -14)!
        XCTAssertEqual(h, 3.98, accuracy: 0.05)
        XCTAssertEqual(CalibrationPlan.durationText(hours: h), "about 4 h")
        XCTAssertEqual(CalibrationPlan.durationText(hours: 0.74), "about 45 min")
        XCTAssertEqual(CalibrationPlan.durationText(hours: 0.1), "under 10 min")
        XCTAssertEqual(CalibrationPlan.durationText(hours: 30), "more than a day")
        XCTAssertNil(CalibrationPlan.drainHours(percent: 80, maxMAh: nil, volts: 11, watts: 10))
        XCTAssertNil(CalibrationPlan.drainHours(percent: 80, maxMAh: 5000, volts: 11, watts: 0.2))   // idle reading: no guess
        XCTAssertEqual(CalibrationPlan.drainHours(percent: 10, maxMAh: 5000, volts: 11, watts: 10), 0)
    }

    func testOvernightStart() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        let night = cal.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 23))!
        let noon = cal.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!
        func go(_ now: Date, enabled: Bool = true, plugged: Bool = true, active: Bool = false, last: Date? = nil, attempt: Date? = nil) -> Bool {
            CalibrationPlan.overnightShouldStart(enabled: enabled, plugged: plugged, taskActive: active, lastCalibrated: last,
                                                 lastAttempt: attempt, now: now, calendar: cal)
        }
        XCTAssertTrue(go(night))
        XCTAssertFalse(go(noon))
        XCTAssertFalse(go(night, enabled: false))
        XCTAssertFalse(go(night, plugged: false))
        XCTAssertFalse(go(night, active: true))
        XCTAssertFalse(go(night, last: night - 10 * 86400))            // calibrated this month
        XCTAssertTrue(go(night, last: night - 31 * 86400))
        XCTAssertFalse(go(night, attempt: night - 3600))               // cancelled tonight: stays cancelled
        XCTAssertTrue(go(night, attempt: night - 86400))
    }

    func testHeatNeverHoldsALowBattery() {
        XCTAssertTrue(HeatLimit.shouldHold(hot: true, percent: 50))
        XCTAssertFalse(HeatLimit.shouldHold(hot: true, percent: HeatLimit.chargeFloor))
        XCTAssertFalse(HeatLimit.shouldHold(hot: true, percent: 6))
        XCTAssertFalse(HeatLimit.shouldHold(hot: false, percent: 50))
    }
}
