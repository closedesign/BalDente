import XCTest
@testable import BalDenteCore

final class ZoneTests: XCTestCase {
    func testMatchesBySSIDCaseInsensitive() {
        var c = Config()
        c.zones[0].networks = ["HomeWiFi"]
        XCTAssertEqual(resolveZone(c, networks: ["homewifi"]).label, "Home")
        XCTAssertEqual(resolveZone(c, networks: ["homewifi"]).upper, 80)
    }
    func testUnknownNetworkUsesDefault() {
        XCTAssertEqual(resolveZone(Config(), networks: ["Cafe"]).label, "Default")
    }
    func testOverrideWins() {
        var c = Config()
        c.zones[0].networks = ["HomeWiFi"]
        c.overrideZone = "School"
        XCTAssertEqual(resolveZone(c, networks: ["HomeWiFi"]).label, "School")
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testReadyByPicksTodayThenSkipsAfterRun() {
        var cs = ChargeSchedule(); cs.enabled = true
        let mon6am = date(2026, 10, 26, 6, 0)               // a Monday
        XCTAssertEqual(cs.nextReady(after: mon6am), date(2026, 10, 26, 7, 30))
        cs.ran = [ChargeSchedule.key(date(2026, 10, 26, 7, 30))]
        XCTAssertEqual(cs.nextReady(after: mon6am), date(2026, 10, 27, 7, 30))
    }

    func testReadyBySkipsWeekend() {
        var cs = ChargeSchedule(); cs.enabled = true
        let fri8am = date(2026, 10, 30, 8, 0)               // Friday, already past 7:30
        XCTAssertEqual(cs.nextReady(after: fri8am), date(2026, 11, 2, 7, 30))
    }

    func testEachDayHasItsOwnTime() {
        var cs = ChargeSchedule(); cs.enabled = true
        cs.slots = [Slot(weekday: 3, hour: 11, minute: 0), Slot(weekday: 4, hour: 16, minute: 0), Slot(weekday: 5, hour: 11, minute: 0)]
        let mon = date(2026, 10, 26, 9, 0)
        XCTAssertEqual(cs.nextReady(after: mon), date(2026, 10, 27, 11, 0))                 // Tue 11:00
        XCTAssertEqual(cs.nextReady(after: date(2026, 10, 27, 12, 0)), date(2026, 10, 28, 16, 0))  // Wed 16:00
        XCTAssertEqual(cs.nextReady(after: date(2026, 10, 28, 17, 0)), date(2026, 10, 29, 11, 0))  // Thu 11:00
    }

    func testSeveralTimesOnOneDayRunInOrder() {
        var cs = ChargeSchedule(); cs.enabled = true
        cs.slots = [Slot(weekday: 3, hour: 17, minute: 0), Slot(weekday: 3, hour: 8, minute: 0)]
        XCTAssertEqual(cs.nextReady(after: date(2026, 10, 27, 7, 0)), date(2026, 10, 27, 8, 0))
        cs.ran = [ChargeSchedule.key(date(2026, 10, 27, 8, 0))]
        XCTAssertEqual(cs.nextReady(after: date(2026, 10, 27, 7, 0)), date(2026, 10, 27, 17, 0))
    }

    func testOldSharedTimeFormatMigrates() throws {
        let json = #"{"enabled":true,"weekdays":[2,4],"hour":8,"minute":15}"#
        let cs = try JSONDecoder().decode(ChargeSchedule.self, from: Data(json.utf8))
        XCTAssertEqual(cs.slots, [Slot(weekday: 2, hour: 8, minute: 15), Slot(weekday: 4, hour: 8, minute: 15)])
    }

    func testDisabledScheduleHasNoNext() {
        XCTAssertNil(ChargeSchedule().nextReady(after: Date()))
    }

    func testLeadGrowsWithDeficit() {
        XCTAssertEqual(ChargeSchedule.leadMinutes(percent: 100), 10)
        XCTAssertGreaterThan(ChargeSchedule.leadMinutes(percent: 50), ChargeSchedule.leadMinutes(percent: 90))
    }

    func testCalibrationTimeIsTonightOrTomorrow() {
        XCTAssertEqual(nextOccurrence(hour: 3, minute: 0, after: date(2026, 10, 26, 23, 0)), date(2026, 10, 27, 3, 0))
        XCTAssertEqual(nextOccurrence(hour: 3, minute: 0, after: date(2026, 10, 27, 1, 30)), date(2026, 10, 27, 3, 0))
    }

    func testSlotKeepsItsOwnPercentAndOldSavesDefaultTo100() throws {
        var cs = ChargeSchedule(); cs.enabled = true
        cs.slots = [Slot(weekday: 3, hour: 11, minute: 0, percent: 80)]
        XCTAssertEqual(cs.nextSlot(after: date(2026, 10, 26, 9, 0))?.slot.percent, 80)
        let old = try JSONDecoder().decode(Slot.self, from: Data(#"{"weekday":2,"hour":7,"minute":30}"#.utf8))
        XCTAssertEqual(old.percent, 100)
    }

    func testLeadScalesWithTarget() {
        XCTAssertLessThan(ChargeSchedule.leadMinutes(percent: 50, target: 80), ChargeSchedule.leadMinutes(percent: 50, target: 100))
    }

    func testConfigWithoutAppearanceStillLoads() throws {
        let json = #"{"zones":[],"defaultUpper":80,"defaultLower":75}"#
        let c = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertNil(c.appearance)
    }

    func testGeofenceMatchesWhenNoWiFiButWiFiWins() {
        var c = Config()
        c.zones[0].networks = ["HomeWiFi"]            // Home
        let schoolID = c.zones[1].id
        XCTAssertEqual(resolveZone(c, networks: [], inside: [schoolID]).label, "School")
        XCTAssertEqual(resolveZone(c, networks: ["HomeWiFi"], inside: [schoolID]).label, "Home")
        XCTAssertEqual(resolveZone(c, networks: [], inside: []).label, "Default")
    }

    func testZoneWithPlaceRoundTrips() throws {
        let z = Zone(name: "Campus", upper: 100, lower: 95, place: Place(latitude: 1.5, longitude: -2.5, radius: 200))
        let back = try JSONDecoder().decode(Zone.self, from: JSONEncoder().encode(z))
        XCTAssertEqual(back.place, z.place)
    }
}

final class ReadySkipTests: XCTestCase {
    private func date(_ d: Int, _ h: Int, _ m: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }
    private func schedule(zone: String?) -> ChargeSchedule {
        var cs = ChargeSchedule(); cs.enabled = true; cs.onlyZone = zone; return cs   // Monday to Friday 7:30, 100%
    }

    func testSkipOnlyAfterStartTimeWhenZoneDiffers() {
        let cs = schedule(zone: "Home")
        // 50% to 100% needs 85 minutes, so the start is 06:05 on Monday 26 Oct.
        XCTAssertNil(ReadySkip.check(cs, activeLabel: "School", percent: 50, taskActive: false, now: date(26, 5, 0)))
        let s = ReadySkip.check(cs, activeLabel: "School", percent: 50, taskActive: false, now: date(26, 6, 30))
        XCTAssertEqual(s?.zone, "Home"); XCTAssertEqual(s?.ready, date(26, 7, 30)); XCTAssertEqual(s?.percent, 100)
    }

    func testNoSkipWhenAnywhereMatchingTaskRunningOrFull() {
        let now = date(26, 6, 30)
        XCTAssertNil(ReadySkip.check(schedule(zone: nil), activeLabel: "School", percent: 50, taskActive: false, now: now))
        XCTAssertNil(ReadySkip.check(schedule(zone: "Home"), activeLabel: "Home", percent: 50, taskActive: false, now: now))
        XCTAssertNil(ReadySkip.check(schedule(zone: "Home"), activeLabel: "School", percent: 50, taskActive: true, now: now))
        XCTAssertNil(ReadySkip.check(schedule(zone: "Home"), activeLabel: "School", percent: 100, taskActive: false, now: now))
    }

    func testZoneNamesWithSpacesMatchTheWireLabel() {
        let cs = schedule(zone: "Home Office")
        XCTAssertNil(ReadySkip.check(cs, activeLabel: "Home_Office", percent: 50, taskActive: false, now: date(26, 6, 30)))
    }

    func testTravelModeCountsAsAnotherLimit() {
        XCTAssertNotNil(ReadySkip.check(schedule(zone: "Home"), activeLabel: "Travel Mode", percent: 50, taskActive: false, now: date(26, 6, 30)))
    }

    func testSkippedEventWording() {
        let e = ChangeEvent.readyBySkipped(zone: "Home", active: "Default", percent: 100, by: date(26, 7, 30))
        XCTAssertEqual(e.category, .readyBy)
        XCTAssertTrue(e.body.contains("Everywhere else"))
    }
}

final class ReadyPreviewTests: XCTestCase {
    private func date(_ d: Int, _ h: Int, _ m: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }
    private func cs(zone: String? = nil) -> ChargeSchedule { var c = ChargeSchedule(); c.enabled = true; c.onlyZone = zone; return c }
    // Monday 26 Oct, 7:30 departure at 100%; from 50% charging starts 06:05.
    private func make(_ c: ChargeSchedule, label: String = "Home", pct: Int = 50, plugged: Bool = true, task: Bool = false, now: Date) -> ReadyPreview? {
        ReadyPreview.make(c, activeLabel: label, percent: pct, plugged: plugged, taskActive: task, now: now)
    }

    func testWillStartThenStartingNow() {
        XCTAssertEqual(make(cs(), now: date(26, 0, 0))?.outcome, .willStart(at: date(26, 6, 5)))
        XCTAssertEqual(make(cs(), now: date(26, 6, 30))?.outcome, .startingNow)
    }

    func testHiddenWhenFarOffOffOrRunning() {
        XCTAssertNil(make(cs(), now: date(25, 0, 0)))                    // Sunday midnight: Monday 7:30 is 31 h away
        XCTAssertNil(make(ChargeSchedule(), now: date(26, 0, 0)))        // Ready by off
        XCTAssertNil(make(cs(), task: true, now: date(26, 6, 30)))
    }

    func testZoneBlockBeatsPowerAndMatchingZoneRuns() {
        let blocked = make(cs(zone: "Home"), label: "School", plugged: false, now: date(26, 0, 0))
        XCTAssertEqual(blocked?.outcome, .blockedByZone(zone: "Home", active: "School"))
        XCTAssertEqual(blocked?.needsAttention, true)
        XCTAssertEqual(make(cs(zone: "Home"), label: "Home", now: date(26, 0, 0))?.outcome, .willStart(at: date(26, 6, 5)))
    }

    func testUnpluggedAndAlreadyFull() {
        XCTAssertEqual(make(cs(), plugged: false, now: date(26, 0, 0))?.outcome, .needsPower(by: date(26, 6, 5)))
        XCTAssertEqual(make(cs(), pct: 100, now: date(26, 0, 0))?.outcome, .alreadyThere)
        XCTAssertTrue(make(cs(), now: date(26, 0, 0))!.detail.contains("6:05"))
    }
}
