import XCTest
@testable import BalDenteCore

final class HabitPlannerTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Europe/Amsterdam")!; return c
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, tz: String = "Europe/Amsterdam") -> Date {
        var c = cal; c.timeZone = TimeZone(identifier: tz)!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    /// Weekday unplugs for `weeks` weeks starting Monday 2026-09-07, at 8:mm with the given minute offsets cycling.
    private func weekdayLog(weeks: Int, minutes: [Int] = [5, 10, 15, 10, 8]) -> HabitLog {
        var log = HabitLog()
        var i = 0
        for w in 0..<weeks {
            for d in 0..<5 {
                let day = at(2026, 9, 7 + w * 7 + d, 8, minutes[i % minutes.count]); i += 1
                log.events.append(HabitEvent(date: day, kind: .unplug, calendar: cal))
            }
        }
        return log
    }

    private var afterFourWeeks: Date { at(2026, 10, 5, 6, 0) }

    func testSuggestsWeekdayMorningPattern() throws {
        let s = try XCTUnwrap(HabitPlanner.suggest(weekdayLog(weeks: 4), now: afterFourWeeks))
        XCTAssertEqual(Set(s.readyBy.keys), Set(2...6))
        for wd in 2...6 { XCTAssertEqual(s.readyBy[wd]! % 5, 0); XCTAssertLessThan(s.readyBy[wd]!, s.departures[wd]!) }
        XCTAssertEqual(s.slots.count, 5)
        XCTAssertTrue(s.slots.allSatisfy { $0.percent == 100 && $0.hour < 8 || ($0.hour == 8 && $0.minute <= 5) })
    }

    func testNothingInTheFirstWeeks() {
        let log = weekdayLog(weeks: 1)
        XCTAssertNil(HabitPlanner.suggest(log, now: at(2026, 9, 12, 12, 0)))
        XCTAssertNil(HabitPlanner.suggest(HabitLog(), now: afterFourWeeks))
    }

    func testTooFewSamplesPerWeekday() {
        // Two weeks of data spread over a long span: only 2 samples per weekday.
        var log = weekdayLog(weeks: 2)
        log.events.append(HabitEvent(date: at(2026, 9, 26, 11, 0), kind: .unplug, calendar: cal))   // a Saturday
        XCTAssertNil(HabitPlanner.suggest(log, now: afterFourWeeks))
    }

    func testInconsistentTimesAreIgnored() {
        // Mondays at 7:00, 10:00, 13:00, 16:00: no cluster holds 60%.
        var log = HabitLog()
        for (w, h) in [7, 10, 13, 16].enumerated() {
            log.events.append(HabitEvent(date: at(2026, 9, 7 + w * 7, h, 0), kind: .unplug, calendar: cal))
        }
        XCTAssertNil(HabitPlanner.suggest(log, now: afterFourWeeks))
    }

    func testOutlierDoesNotMoveTheTime() throws {
        let m = [8 * 60 + 10, 8 * 60 + 12, 8 * 60 + 8, 8 * 60 + 10, 14 * 60]
        XCTAssertEqual(HabitPlanner.typicalMinute(m), 8 * 60 + 10)
        XCTAssertNil(HabitPlanner.typicalMinute([480, 490]))
    }

    func testFirstUnplugOfTheDayWins() {
        var log = HabitLog()
        let d = at(2026, 9, 7, 8, 0)
        log.events = [HabitEvent(date: d.addingTimeInterval(5 * 3600), kind: .unplug, calendar: cal),
                      HabitEvent(date: d.addingTimeInterval(-600), kind: .zoneExit, calendar: cal),
                      HabitEvent(date: d, kind: .unplug, calendar: cal)]
        let f = HabitPlanner.firstDepartures(log)
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f.first?.kind, .unplug)
        XCTAssertEqual(f.first?.minute, 8 * 60)
    }

    func testZoneExitCountsWhenNoUnplug() {
        var log = HabitLog()
        log.events = [HabitEvent(date: at(2026, 9, 7, 9, 0), kind: .zoneExit, calendar: cal)]
        XCTAssertEqual(HabitPlanner.firstDepartures(log).first?.kind, .zoneExit)
    }

    func testLateNightBelongsToPreviousDay() {
        let e = HabitEvent(date: at(2026, 9, 8, 1, 30), kind: .unplug, calendar: cal)   // Tuesday 1:30 AM
        XCTAssertEqual(e.day, "2026-09-07")
        XCTAssertEqual(e.weekday, 2)                                                    // counts as Monday night
        XCTAssertEqual(e.minute, 1440 + 90)
    }

    func testAfterMidnightPatternIsNotSuggested() {
        var log = HabitLog()
        for w in 0..<4 { log.events.append(HabitEvent(date: at(2026, 9, 8 + w * 7, 1, 0), kind: .unplug, calendar: cal)) }
        XCTAssertNil(HabitPlanner.suggest(log, now: afterFourWeeks))
    }

    func testDSTAndTimeZoneDoNotShiftSamples() throws {
        // Europe/Amsterdam leaves DST on 2026-10-25. Unplugs at 8:10 local on Mondays before and after stay at 8:10.
        var log = HabitLog()
        for d in [5, 12, 19, 26] { log.events.append(HabitEvent(date: at(2026, 10, d, 8, 10), kind: .unplug, calendar: cal)) }
        // A Monday in New York, logged with that time zone's calendar, still at 8:10 local.
        var ny = Calendar(identifier: .gregorian); ny.timeZone = TimeZone(identifier: "America/New_York")!
        log.events.append(HabitEvent(date: at(2026, 11, 2, 8, 10, tz: "America/New_York"), kind: .unplug, calendar: ny))
        XCTAssertTrue(log.events.allSatisfy { $0.minute == 8 * 60 + 10 && $0.weekday == 2 })
        let s = try XCTUnwrap(HabitPlanner.suggest(log, now: at(2026, 11, 3, 6, 0)))
        XCTAssertEqual(s.readyBy[2], 8 * 60)
    }

    func testReplugDropsTheUnplugAndPruneKeepsEightWeeks() {
        var log = HabitLog()
        let d = at(2026, 9, 7, 8, 0)
        log.record(HabitEvent(date: d, kind: .unplug, calendar: cal), now: d)
        log.plugged(at: d.addingTimeInterval(120))
        XCTAssertTrue(log.events.isEmpty)
        log.record(HabitEvent(date: d, kind: .unplug, calendar: cal), now: d)
        log.plugged(at: d.addingTimeInterval(3600))
        XCTAssertEqual(log.events.count, 1)
        log.prune(now: d.addingTimeInterval(9 * 7 * 86400))
        XCTAssertTrue(log.events.isEmpty)
    }

    func testCoveredAndMerged() throws {
        let s = try XCTUnwrap(HabitPlanner.suggest(weekdayLog(weeks: 4), now: afterFourWeeks))
        var cs = ChargeSchedule()
        XCTAssertFalse(HabitPlanner.isCovered(s, by: cs))                 // disabled schedule covers nothing
        cs.enabled = true; cs.slots = s.slots
        XCTAssertTrue(HabitPlanner.isCovered(s, by: cs))
        cs.slots = s.slots.map { var x = $0; x.hour -= 2; return x }      // full far too early: topped-up window ends before you leave
        XCTAssertFalse(HabitPlanner.isCovered(s, by: cs))
        cs.slots = [Slot(weekday: 7, hour: 10, minute: 0, percent: 90), Slot(weekday: 2, hour: 6, minute: 0)]
        let merged = HabitPlanner.merged(s, into: cs)
        XCTAssertEqual(merged.count, 6)                                   // Saturday kept, Monday replaced
        XCTAssertTrue(merged.contains(Slot(weekday: 7, hour: 10, minute: 0, percent: 90)))
        XCTAssertFalse(merged.contains(Slot(weekday: 2, hour: 6, minute: 0)))
    }

    func testDescribeAndSpec() {
        let en = { () -> Calendar in var c = Calendar(identifier: .gregorian); c.locale = Locale(identifier: "en_US"); return c }()
        XCTAssertEqual(HabitPlanner.describe([2: 490, 3: 490, 4: 490, 5: 490, 6: 490], calendar: en), "8:10 on weekdays")
        XCTAssertEqual(HabitPlanner.describe([2: 490, 4: 492, 7: 570], calendar: en), "8:10 on Mon, Wed · 9:30 on Sat")
        XCTAssertEqual(HabitPlanner.dayList([1, 7], calendar: en), "weekends")
        XCTAssertEqual(ChargeSchedule.spec([Slot(weekday: 2, hour: 7, minute: 5, percent: 90)]), "2@07:05@90")
    }

    func testSimilarityAndQuestion() {
        let a = HabitSuggestion(departures: [2: 490, 3: 490], readyBy: [2: 480, 3: 480])
        var b = a; b.readyBy = [2: 495, 3: 470]
        XCTAssertTrue(a.isSimilar(to: b))
        b.readyBy = [2: 540, 3: 480]
        XCTAssertFalse(a.isSimilar(to: b))
        b.readyBy = [2: 480]
        XCTAssertFalse(a.isSimilar(to: b))
        XCTAssertTrue(a.question.hasPrefix("You usually unplug around 8:10 on "))
        XCTAssertTrue(a.question.hasSuffix("Charge to 100% by 8:00 on Mon, Tue?") || a.question.contains("8:00"))
    }

    func testLogRoundTrips() throws {
        let log = weekdayLog(weeks: 1)
        let back = try JSONDecoder().decode(HabitLog.self, from: JSONEncoder().encode(log))
        XCTAssertEqual(back, log)
    }
}
