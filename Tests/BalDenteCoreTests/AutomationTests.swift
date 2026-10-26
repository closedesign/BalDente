import XCTest
@testable import BalDenteCore

final class ScheduledTaskTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: m))!
    }
    private func task(_ r: ScheduledTask.Repeat, anchor: Date, h: Int = 9, m: Int = 0, catchUp: Bool = false) -> ScheduledTask {
        ScheduledTask(id: "t1", action: .topUp, repeats: r, hour: h, minute: m, anchor: anchor, catchUp: catchUp)
    }

    func testDailyAndWeekdays() {
        let mon = date(2026, 10, 26)   // Monday
        XCTAssertEqual(task(.daily, anchor: mon).nextRun(after: date(2026, 10, 26, 10), calendar: cal), date(2026, 10, 27, 9))
        let wk = task(.weekdays, anchor: mon)
        XCTAssertEqual(wk.nextRun(after: date(2026, 10, 30, 10), calendar: cal), date(2026, 11, 2, 9))      // Friday evening to Monday
    }

    func testWeeklyAndBiweekly() {
        let tue = date(2026, 10, 27)
        XCTAssertEqual(task(.weekly, anchor: tue).nextRun(after: date(2026, 10, 27, 10), calendar: cal), date(2026, 11, 3, 9))
        let bi = task(.biweekly, anchor: tue)
        XCTAssertEqual(bi.nextRun(after: date(2026, 10, 27, 10), calendar: cal), date(2026, 11, 10, 9))     // skips next week
        XCTAssertNil(bi.occurrence(on: date(2026, 11, 3), calendar: cal))
    }

    func testMonthlyClampsToShortMonthsAndYearlyHandlesLeapDay() {
        let jan31 = task(.monthly, anchor: date(2026, 1, 31))
        XCTAssertEqual(jan31.occurrence(on: date(2026, 2, 28), calendar: cal), date(2026, 2, 28, 9))
        XCTAssertNil(jan31.occurrence(on: date(2026, 2, 27), calendar: cal))
        let leap = task(.yearly, anchor: date(2024, 2, 29))
        XCTAssertEqual(leap.occurrence(on: date(2027, 2, 28), calendar: cal), date(2027, 2, 28, 9))
        XCTAssertNil(leap.occurrence(on: date(2027, 3, 1), calendar: cal))
    }

    func testOnceNeverBeforeAnchorAndOnlyThatDay() {
        let t = task(.once, anchor: date(2026, 10, 30))
        XCTAssertNil(t.occurrence(on: date(2026, 10, 29), calendar: cal))
        XCTAssertNotNil(t.occurrence(on: date(2026, 10, 30), calendar: cal))
        XCTAssertNil(t.occurrence(on: date(2026, 10, 31), calendar: cal))
    }

    func testDueWindowsAndCatchUp() {
        var t = task(.daily, anchor: date(2026, 10, 1))
        XCTAssertEqual(t.due(at: date(2026, 10, 26, 9, 5), calendar: cal), date(2026, 10, 26, 9))
        XCTAssertNil(t.due(at: date(2026, 10, 26, 9, 30), calendar: cal))               // too late without catch-up
        t.catchUp = true
        XCTAssertEqual(t.due(at: date(2026, 10, 26, 14, 0), calendar: cal), date(2026, 10, 26, 9))
        t.lastRun = date(2026, 10, 26, 9)
        XCTAssertNil(t.due(at: date(2026, 10, 26, 14, 0), calendar: cal))               // already ran
        XCTAssertNil(t.due(at: date(2026, 10, 26, 8, 0), calendar: cal))                // not yet
        t.lastRun = nil; t.enabled = false
        XCTAssertNil(t.due(at: date(2026, 10, 26, 9, 1), calendar: cal))
    }

    func testCatchUpAfterMidnightFindsYesterday() {
        let t = task(.daily, anchor: date(2026, 10, 1), h: 23, m: 30, catchUp: true)
        XCTAssertEqual(t.due(at: date(2026, 10, 27, 6, 0), calendar: cal), date(2026, 10, 26, 23, 30))
    }

    func testWireRoundTripAndRejection() {
        let t = ScheduledTask(id: "abc123", action: .discharge, percent: 60, repeats: .weekly, hour: 7, minute: 15,
                              anchor: Date(timeIntervalSince1970: 1_800_000_000), enabled: false, catchUp: false)
        let tokens = t.wire.split(separator: " ").map(String.init).dropFirst(2)
        XCTAssertEqual(ScheduledTask.parse(Array(tokens)), t)
        var bad = Array(tokens)
        bad[2] = "5"; XCTAssertNil(ScheduledTask.parse(bad))                              // discharge target below 20
        bad = Array(tokens); bad[0] = "../x"; XCTAssertNil(ScheduledTask.parse(bad))      // id must be plain letters and digits
        bad = Array(tokens); bad[4] = "24"; XCTAssertNil(ScheduledTask.parse(bad))
        bad = Array(tokens); bad[6] = "99999999999"; XCTAssertNil(ScheduledTask.parse(bad))
        XCTAssertNil(ScheduledTask.parse(Array(tokens.dropLast())))
    }

    func testUpsertKeepsLastRunCapsAndSeedsNewTasks() {
        let now = date(2026, 10, 26, 12)
        var list = TaskBook.upsert([], task(.daily, anchor: now), now: now)
        XCTAssertEqual(list[0].lastRun, now)                                              // new tasks don't fire for the past
        list[0].lastRun = date(2026, 10, 26, 9)
        var edited = list[0]; edited.hour = 10; edited.lastRun = nil
        XCTAssertEqual(TaskBook.upsert(list, edited, now: now)[0].lastRun, date(2026, 10, 26, 9))
        for i in 0..<30 { var t = task(.daily, anchor: now); t.id = "x\(i)"; list = TaskBook.upsert(list, t, now: now) }
        XCTAssertEqual(list.count, ScheduledTask.maxCount)
    }

    func testOldStateFileStillDecodes() throws {
        let old = #"{"enabled":true,"upper":70,"lower":65,"label":"Home"}"#
        let s = try JSONDecoder().decode(LimiterState.self, from: Data(old.utf8))
        XCTAssertEqual(s.upper, 70); XCTAssertTrue(s.tasks.isEmpty); XCTAssertFalse(s.stopWhenSleeping); XCTAssertEqual(s.led, .system)
        let roundTrip = try JSONDecoder().decode(LimiterState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(roundTrip, s)
    }
}

final class LeaveTimeTests: XCTestCase {
    func testSubtractsTravelAndCrossesMidnightBackwards() {
        let a = LeaveTime.leave(arriveWeekday: 2, hour: 8, minute: 30, travel: 60)
        XCTAssertEqual([a.weekday, a.hour, a.minute], [2, 7, 30])
        let b = LeaveTime.leave(arriveWeekday: 2, hour: 0, minute: 10, travel: 30)        // Monday 00:10 leaves Sunday 23:40
        XCTAssertEqual([b.weekday, b.hour, b.minute], [1, 23, 40])
        let c = LeaveTime.leave(arriveWeekday: 1, hour: 0, minute: 10, travel: 30)        // Sunday wraps to Saturday
        XCTAssertEqual([c.weekday, c.hour, c.minute], [7, 23, 40])
    }

    func testArriveInvertsLeaveAndClampsTravel() {
        for w in 1...7 { for t in [0, 45, 240] {
            let l = LeaveTime.leave(arriveWeekday: w, hour: 0, minute: 5, travel: t)
            let a = LeaveTime.arrive(leaveWeekday: l.weekday, hour: l.hour, minute: l.minute, travel: t)
            XCTAssertEqual([a.weekday, a.hour, a.minute], [w, 0, 5])
        } }
        XCTAssertEqual(LeaveTime.clampTravel(9999), LeaveTime.maxTravelMinutes)
        XCTAssertEqual(LeaveTime.clampTravel(-5), 0)
    }

    func testChargeScheduleTravelDefaultsToZeroForOldFiles() throws {
        let cs = try JSONDecoder().decode(ChargeSchedule.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertEqual(cs.travelMinutes, 0)
    }
}

final class PowerAndAutomationTests: XCTestCase {
    private func wrap(_ v: Int64) -> UInt64 { UInt64(bitPattern: v) }

    func testPowerFlowSignsAndWrapping() {
        let charging = PowerFlow(systemPowerInMW: 60_000, systemLoadMW: 20_000, batteryPowerMW: wrap(40_000))
        XCTAssertEqual(charging.toBattery, 40, accuracy: 0.01); XCTAssertEqual(charging.fromBattery, 0)
        let unplugged = PowerFlow(systemPowerInMW: 0, systemLoadMW: 11_000, batteryPowerMW: wrap(-11_000))
        XCTAssertEqual(unplugged.fromBattery, 11, accuracy: 0.01); XCTAssertEqual(unplugged.toBattery, 0)
        XCTAssertEqual(unplugged.summary, "Battery powers the Mac: 11 W")
        let garbage = PowerFlow(systemPowerInMW: wrap(-5), systemLoadMW: UInt64.max / 2, batteryPowerMW: 0)
        XCTAssertEqual(garbage.fromCharger, 0); XCTAssertEqual(garbage.toMac, 0); XCTAssertTrue(garbage.isIdle)
        XCTAssertEqual(charging.summary, "Charger 60 W: Mac 20 W, battery 40 W")
    }

    func testMagSafeLEDValues() {
        XCTAssertNil(MagSafeLED.system.value(plugged: true, holding: true))
        XCTAssertEqual(MagSafeLED.off.value(plugged: false, holding: false), 1)
        XCTAssertEqual(MagSafeLED.indicate.value(plugged: true, holding: true), 3)
        XCTAssertEqual(MagSafeLED.indicate.value(plugged: true, holding: false), 4)
        XCTAssertNil(MagSafeLED.indicate.value(plugged: false, holding: false))
    }

    func testAutoDischargeGuards() {
        func t(pct: Int = 90, upper: Int = 80, plugged: Bool = true, task: Bool = false, override: Bool = false, enabled: Bool = true,
               ready: ChargeSchedule = ChargeSchedule()) -> Int? {
            AutoDischarge.target(enabled: enabled, plugged: plugged, percent: pct, limitUpper: upper, limitEnabled: upper < 100,
                                 taskActive: task, overrideActive: override, readyBy: ready, now: Date(timeIntervalSince1970: 1_800_000_000))
        }
        XCTAssertEqual(t(), 80)
        XCTAssertNil(t(pct: 82)); XCTAssertNil(t(plugged: false)); XCTAssertNil(t(task: true)); XCTAssertNil(t(override: true))
        XCTAssertNil(t(enabled: false)); XCTAssertNil(t(upper: 100)); XCTAssertNil(t(pct: 40, upper: 10))
        var soon = ChargeSchedule(); soon.enabled = true
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let c = Calendar.current.dateComponents([.weekday, .hour, .minute], from: now.addingTimeInterval(3600))
        soon.slots = [Slot(weekday: c.weekday!, hour: c.hour!, minute: c.minute!)]
        XCTAssertNil(t(ready: soon))                                                       // Ready by in an hour: don't drain first
    }

    func testAutomationURLs() {
        func p(_ s: String) -> AutomationAction? { AutomationURL.parse(URL(string: s)!) }
        XCTAssertEqual(p("baldente://topup"), .topUp(true))
        XCTAssertEqual(p("baldente://topup/off"), .topUp(false))
        XCTAssertEqual(p("baldente://travel/on"), .travel(true))
        XCTAssertEqual(p("baldente://discharge/60"), .discharge(to: 60))
        XCTAssertNil(p("baldente://discharge/5")); XCTAssertNil(p("baldente://discharge/abc")); XCTAssertNil(p("baldente://discharge"))
        XCTAssertEqual(p("baldente://lowpower/off"), .lowPower(false)); XCTAssertNil(p("baldente://lowpower"))
        XCTAssertNil(p("baldente://format-disk")); XCTAssertNil(p("https://topup")); XCTAssertNil(p("baldente://topup/maybe"))
        XCTAssertEqual(p("BALDENTE://Calibrate"), .calibrate)
    }

    func testAutomationStateNames() {
        var st = LimiterState(); st.upper = 80; st.lower = 75
        func s(_ pct: Int, adapter: Bool, hot: Bool = false) -> Status { Status(percent: pct, adapterOn: adapter, state: st, backend: "x", tempC: 31.25, heatHold: hot) }
        XCTAssertEqual(AutomationState.name(s(60, adapter: true)), "Charging")
        XCTAssertEqual(AutomationState.name(s(80, adapter: false)), "Pause")
        XCTAssertEqual(AutomationState.name(s(78, adapter: false)), "Sailing")
        XCTAssertEqual(AutomationState.name(s(60, adapter: true, hot: true)), "HeatProtect")
        st.task.kind = "topup"; XCTAssertEqual(AutomationState.name(s(60, adapter: true)), "Topup")
        XCTAssertEqual(AutomationState.value("percent", s(60, adapter: true)), "60")
        XCTAssertEqual(AutomationState.value("temperature", s(60, adapter: true)), "31.2")
        XCTAssertNil(AutomationState.value("nope", s(60, adapter: true)))
    }

    func testReadyPreviewHotBattery() {
        let cal = Calendar.current
        let mon = cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 0))!
        var cs = ChargeSchedule(); cs.enabled = true
        let p = ReadyPreview.make(cs, activeLabel: "Home", percent: 50, plugged: true, tempC: 47, taskActive: false, now: mon)
        XCTAssertEqual(p?.outcome, .tooHot(tempC: 47)); XCTAssertEqual(p?.needsAttention, true)
        XCTAssertEqual(ReadyPreview.make(cs, activeLabel: "Home", percent: 50, plugged: true, tempC: 30, taskActive: false, now: mon)?.outcome,
                       .willStart(at: cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 6, minute: 5))!))
    }
}

final class LEDAndWaveTests: XCTestCase {
    func testCustomLEDColoursAndByteValues() {
        XCTAssertEqual(MagSafeLED.custom.value(plugged: true, holding: true, atLimit: .off, charging: .green), 1)
        XCTAssertEqual(MagSafeLED.custom.value(plugged: true, holding: false, atLimit: .off, charging: .green), 3)
        XCTAssertEqual(MagSafeLED.custom.value(plugged: true, holding: false, atLimit: .green, charging: .system), 0)
        XCTAssertNil(MagSafeLED.custom.value(plugged: false, holding: true))
        XCTAssertEqual(LEDColor.allCases.map(\.byte), [0, 1, 3, 4])
        var s = LimiterState(); s.led = .custom; s.ledAtLimit = .orange; s.ledCharging = .off
        let back = try? JSONDecoder().decode(LimiterState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back?.ledAtLimit, .orange); XCTAssertEqual(back?.ledCharging, .off)
    }

    func testWaveSettingOneIsHalfTheOldRate() {
        XCTAssertEqual(WaveClock.rate(forSetting: 1), 0.5)
        XCTAssertEqual(WaveClock.rate(forSetting: 6), 3)
        XCTAssertEqual(WaveClock.rate(forSetting: 0.2), 0.1)
        XCTAssertEqual(WaveClock.rate(forSetting: 0.1), WaveClock.speedRange.lowerBound)   // clamped, never below the slowest rate
        XCTAssertEqual(WaveClock.rate(forSetting: 100), WaveClock.speedRange.upperBound)
        XCTAssertEqual(WaveClock.rate(forSetting: .nan), 0.5)
        var c = WaveClock(); let t0 = Date()
        c.advance(now: t0, speed: WaveClock.rate(forSetting: 1), cycle: 1.8)
        c.advance(now: t0.addingTimeInterval(0.2), speed: WaveClock.rate(forSetting: 1), cycle: 1.8)
        XCTAssertEqual(c.elapsed, 0.1, accuracy: 1e-6)
    }
}
