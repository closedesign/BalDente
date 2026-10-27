import XCTest
@testable import BalDenteCore

final class OnboardingTests: XCTestCase {
    // MARK: Defaults explainer

    func testDefaultLinesComeFromConfig() {
        let l = Defaults.lines()
        XCTAssertEqual(l.map(\.name), ["Home", "School", "Travel", "Everywhere else"])
        XCTAssertEqual(l.first?.text, "Home: holds at 80%, resumes at 75%")
        XCTAssertEqual(l[1].text, "School: holds at 80%, resumes at 75%")
        XCTAssertEqual(l[2].text, "Travel: charges to 100%")
        XCTAssertEqual(l.last?.upper, Config().defaultUpper)
        XCTAssertTrue(Defaults.heatText.contains("\(HeatLimit.defaultLimit)"))
    }

    func testEverywhere80KeepsZonesAndChangesOnlyLimits() {
        var c = Config(); c.zones[0].networks = ["HomeNet"]
        let p = Defaults.apply(.everywhere80, to: c)
        XCTAssertEqual(p.zones.map(\.name), c.zones.map(\.name))
        XCTAssertEqual(p.zones[0].networks, ["HomeNet"])
        XCTAssertTrue(p.zones.allSatisfy { $0.upper == 80 && $0.lower == 75 })
        XCTAssertEqual(p.defaultUpper, 80)
        XCTAssertEqual(Defaults.apply(.keep, to: c), c)
    }

    // MARK: Hold hint

    func testHoldHintEdgeCases() {
        var h = HoldHint()
        XCTAssertEqual(h.message(label: "Home", upper: 50, helperRunning: true, zonesMatched: true, locationAllowed: true),
                       "Holding at 50% (Home zone). Need a full battery?")
        XCTAssertTrue(h.message(label: "Default", upper: 80, helperRunning: true, zonesMatched: false, locationAllowed: true)!.contains("Everywhere else"))
        XCTAssertTrue(h.message(label: "Default", upper: 80, helperRunning: true, zonesMatched: false, locationAllowed: false)!.contains("Allow Location"))
        XCTAssertNil(h.message(label: "Home", upper: 50, helperRunning: false, zonesMatched: true, locationAllowed: true))   // no helper, no limit
        XCTAssertNil(h.message(label: "School", upper: 100, helperRunning: true, zonesMatched: true, locationAllowed: true))
        XCTAssertNil(h.message(label: "Top Up", upper: 100, helperRunning: true, zonesMatched: true, locationAllowed: true))
        XCTAssertTrue(h.message(label: "Home", upper: 50, helperRunning: true, zonesMatched: true, locationAllowed: true, onBattery: true)!
            .hasPrefix("Charging will stop at 50%"))
        h.uses = HoldHint.enoughUses
        XCTAssertNil(h.message(label: "Home", upper: 50, helperRunning: true, zonesMatched: true, locationAllowed: true))
        h = HoldHint(); h.dismissed = true
        XCTAssertTrue(h.retired)
    }

    func testTutorialVersioning() {
        XCTAssertTrue(TutorialVersion.shouldShow(seen: 0, firstLaunch: true))
        XCTAssertFalse(TutorialVersion.shouldShow(seen: 0, firstLaunch: false))        // upgraders get What's New
        XCTAssertFalse(TutorialVersion.shouldShow(seen: TutorialVersion.current, firstLaunch: true))
    }

    // MARK: What's New

    private let changelog = """
    # Changelog

    ## Road to 1.0
    - not a version

    ## 0.6 (pre-release)
    - Tutorial on first launch.
    - Habit suggestions that
      span two lines.

    ## 0.5
    - Old stuff.
    """

    func testWhatsNewSection() {
        XCTAssertEqual(WhatsNew.items(for: "0.6", in: changelog), ["Tutorial on first launch.", "Habit suggestions that span two lines."])
        XCTAssertEqual(WhatsNew.items(for: "0.5", in: changelog), ["Old stuff."])
        XCTAssertNil(WhatsNew.items(for: "0.7", in: changelog))
        XCTAssertNil(WhatsNew.items(for: "0.6", in: ""))
    }

    func testWhatsNewShowRules() {
        XCTAssertFalse(WhatsNew.shouldShow(current: "0.6", lastSeen: nil, firstLaunch: true))
        XCTAssertTrue(WhatsNew.shouldShow(current: "0.6", lastSeen: nil, firstLaunch: false))
        XCTAssertTrue(WhatsNew.shouldShow(current: "0.10", lastSeen: "0.9", firstLaunch: false))
        XCTAssertFalse(WhatsNew.shouldShow(current: "0.6", lastSeen: "0.6", firstLaunch: false))
        XCTAssertFalse(WhatsNew.shouldShow(current: "0.5", lastSeen: "0.6", firstLaunch: false))   // downgrade
        XCTAssertFalse(WhatsNew.shouldShow(current: "dev", lastSeen: nil, firstLaunch: false))
    }

    // MARK: Activity log and notification wording

    func testActivityLogCapsAndCoalesces() {
        var log = ActivityLog()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        log.add(ActivityEntry(date: t0, category: .zones, title: "Switched to Home: 50%", detail: ""))
        log.add(ActivityEntry(date: t0.addingTimeInterval(10), category: .zones, title: "Switched to Home: 50%", detail: "again"))
        XCTAssertEqual(log.entries.count, 1)
        XCTAssertEqual(log.entries.first?.detail, "again")
        for i in 0..<(ActivityLog.cap + 20) {
            log.add(ActivityEntry(date: t0.addingTimeInterval(Double(100 + i * 100)), category: .heat, title: "E\(i)", detail: ""))
        }
        XCTAssertEqual(log.entries.count, ActivityLog.cap)
        XCTAssertEqual(log.entries.first?.title, "E\(ActivityLog.cap + 19)")    // newest first
        log.clear()
        XCTAssertTrue(log.entries.isEmpty)
    }

    func testActivityLogPersists() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("activity-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var log = ActivityLog()
        log.add(ActivityEntry(.heat(on: true, limit: 35), at: Date(timeIntervalSince1970: 1_800_000_000)))
        log.save(to: url)
        XCTAssertEqual(ActivityLog.load(from: url), log)
        try Data("garbage".utf8).write(to: url)
        XCTAssertEqual(ActivityLog.load(from: url), ActivityLog())          // a corrupt file starts fresh, never crashes
    }

    func testChangeWording() {
        let z = ChangeEvent.limit(from: "Default", to: "Home", upper: 50, lower: 45, reason: "connected to HomeNet")
        XCTAssertEqual(z.category, .zones)
        XCTAssertEqual(z.title, "Switched to Home: 50%")
        XCTAssertEqual(z.body, "Because: connected to HomeNet. Charging holds at 50%, resumes at 45%.")
        let t = ChangeEvent.limit(from: "Home", to: "Top Up", upper: 100, lower: 99, reason: nil)
        XCTAssertEqual(t.category, .manual)
        let back = ChangeEvent.limit(from: "Top Up", to: "Default", upper: 80, lower: 75, reason: "x")
        XCTAssertEqual(back.title, "Back to Everywhere else: 80%")
        XCTAssertTrue(back.body.hasPrefix("Top Up finished."))
        XCTAssertEqual(ChangeEvent.heat(on: true, limit: 35).category, .heat)
        XCTAssertTrue(ChangeEvent.heat(on: true, limit: 35).body.contains("35"))
        XCTAssertEqual(ChangeEvent.readyByFinished(calendar: true, backTo: "Home").title, "Calendar Ready by finished, back to Home")
        XCTAssertEqual(ChangeEvent.helperOffline.category, .helper)
    }

    // MARK: Zones and labels

    func testWireLabel() {
        XCTAssertEqual(Target.wire("Home Office"), "Home_Office")
        XCTAssertEqual(Target.wire(""), "zone")
        XCTAssertEqual(Target.wire("  "), "__")
        XCTAssertEqual(Target.wire("a\nb\tc"), "a_b_c")
        XCTAssertEqual(Target.wire("Café 家"), "Café_家")
        XCTAssertEqual(Target.wire(String(repeating: "x", count: 200)).count, 64)
        XCTAssertEqual(Target.wire(Target.wire("Home Office")), "Home_Office")   // idempotent: the helper re-applies it
    }

    func testReservedAndDuplicateNames() {
        XCTAssertEqual(uniqueZoneName("Default", existing: []), "Default 2")
        var c = Config()
        c.zones.append(Zone(name: "home", upper: 80, lower: 75))
        c.zones.append(Zone(name: "Top Up", upper: 80, lower: 75))
        c.zones.append(Zone(name: "  ", upper: 80, lower: 75))
        let s = c.sanitized()
        XCTAssertEqual(s.zones.map(\.name), ["Home", "School", "Travel", "home 2", "Top Up 2", "Zone"])
    }

    func testResolveGivesAReasonWithoutChangingEquality() {
        var c = Config(); c.zones[0].networks = ["HomeNet"]
        let t = resolveZone(c, networks: ["homenet"])
        XCTAssertEqual(t.reason, "connected to HomeNet")
        XCTAssertEqual(resolveZone(Config(), networks: []).reason, "no zone has a Wi-Fi network or place yet")
        var other = t; other.reason = "different"
        XCTAssertEqual(t, other)
    }

    func testHistoryKeepsLastRowOfADuplicatedDayAndDropsImpossibleValues() {
        let csv = "date,health_percent,cycles,battery_percent\n2026-10-01,90,1,50\n2026-10-02,91,2,50\n2026-10-01,93,3,-4\n2026-10-03,250,-1,50\n\n"
        let p = HealthHistory.parse(csv)
        XCTAssertEqual(p.count, 3)
        XCTAssertEqual(p[0].health, 93); XCTAssertEqual(p[0].cycles, 3); XCTAssertNil(p[0].battery)
        XCTAssertNil(p[2].health); XCTAssertNil(p[2].cycles)
        XCTAssertTrue(HealthHistory.parse("").isEmpty)
        XCTAssertTrue(HealthHistory.parse("date,health_percent,cycles,battery_percent\n").isEmpty)
    }
}

final class LimitPauseTests: XCTestCase {
    func testEnd() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(LimitPause.end(hours: 2, from: now).timeIntervalSince(now), 7200)
        XCTAssertEqual(LimitPause.end(hours: 0, from: now).timeIntervalSince(now), 3600)
    }
    func testUntilTextAddsDayOnlyWhenNeeded() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!; cal.locale = Locale(identifier: "en_US")
        let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 10))!
        XCTAssertEqual(LimitPause.untilText(now.addingTimeInterval(7200), now: now, calendar: cal).replacingOccurrences(of: "\u{202F}", with: " "), "until 12:00 PM")
        XCTAssertTrue(LimitPause.untilText(now.addingTimeInterval(86400), now: now, calendar: cal).hasPrefix("until Tue"))
    }
}
