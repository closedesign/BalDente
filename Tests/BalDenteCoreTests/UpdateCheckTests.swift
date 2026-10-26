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
        let r = UpdateCheck.Release(version: "0.7", page: URL(string: "https://x")!, dmg: nil)
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

final class SettingsBackupTests: XCTestCase {
    func testFingerprintDetectsChange() {
        var c = Config()
        let a = SettingsFingerprint(config: c, readyBy: nil)
        XCTAssertEqual(a.differences(to: SettingsFingerprint(config: c, readyBy: nil)), [])
        c.zones[0].upper = 60
        XCTAssertFalse(a.differences(to: SettingsFingerprint(config: c, readyBy: nil)).isEmpty)
    }
    func testReadyByOnlyComparedWhenBothKnown() {
        let c = Config(); var r = ChargeSchedule(); r.enabled = true
        let a = SettingsFingerprint(config: c, readyBy: r)
        XCTAssertEqual(a.differences(to: SettingsFingerprint(config: c, readyBy: nil)), [])
        var r2 = r; r2.ran = ["x"]
        XCTAssertEqual(a.differences(to: SettingsFingerprint(config: c, readyBy: r2)), [])   // bookkeeping ignored
        r2.enabled = false
        XCTAssertEqual(a.differences(to: SettingsFingerprint(config: c, readyBy: r2)), ["Ready by"])
    }
    func testBackupSaveListPruneLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bd-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        var store = BackupStore(directory: dir); store.keep = 2
        let data = try JSONEncoder().encode(Config())
        for i in 0..<3 { store.save(data, version: "0.\(i)", date: Date().addingTimeInterval(Double(i))) }
        let l = store.list()
        XCTAssertEqual(l.count, 2)
        XCTAssertNotNil(store.load(l[0]))
        XCTAssertNil(store.save(Data(), version: "0.9"))
    }
    func testReleaseDmgOnlyFromOwnRepo() {
        let json = """
        [{"tag_name":"v0.8","html_url":"https://github.com/closedesign/BalDente/releases/tag/v0.8","assets":[
          {"name":"BalDente.dmg","browser_download_url":"https://evil.example/BalDente.dmg"}]},
         {"tag_name":"v0.7","html_url":"https://github.com/closedesign/BalDente/releases/tag/v0.7","assets":[
          {"name":"BalDente.dmg","browser_download_url":"https://github.com/closedesign/BalDente/releases/download/v0.7/BalDente.dmg"}]}]
        """
        let r = UpdateCheck.latest(from: Data(json.utf8))
        XCTAssertEqual(r?.version, "0.8"); XCTAssertNil(r?.dmg)
    }
}
