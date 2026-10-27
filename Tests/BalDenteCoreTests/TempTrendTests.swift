import XCTest
@testable import BalDenteCore

final class TempTrendTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func trend(_ temps: [Double], every s: TimeInterval = 20) -> TempTrend {
        var t = TempTrend()
        for (i, c) in temps.enumerated() { t.add(c, at: t0 + Double(i) * s) }
        return t
    }

    func testFallingRateAndEta() {
        // 0.04 °C per minute down, sampled each minute for 10 minutes: 38.4 → 38.0.
        let t = trend((0...10).map { 38.4 - 0.04 * Double($0) }, every: 60)
        XCTAssertEqual(t.ratePerMinute()!, -0.04, accuracy: 0.001)
        XCTAssertEqual(t.minutesUntil(37), 25)
        XCTAssertEqual(t.summary(resumeAt: 37), "38.0 °C, falling 0.4 °C every 10 min. Charging resumes at 37 °C in about 25 min.")
    }

    func testRisingAndSteady() {
        XCTAssertEqual(trend((0...10).map { 38 + 0.05 * Double($0) }, every: 60).summary(resumeAt: 37),
                       "38.5 °C, rising 0.5 °C every 10 min. Charging resumes at 37 °C.")
        XCTAssertEqual(trend(Array(repeating: 38.2, count: 12)).summary(resumeAt: 37),
                       "38.2 °C, holding steady. Charging resumes at 37 °C.")
    }

    func testNeedsEnoughData() {
        XCTAssertNil(trend([38, 37.9]).ratePerMinute())
        XCTAssertNil(trend([38, 37.9, 37.8], every: 20).ratePerMinute())   // only 40 s of data
        XCTAssertEqual(trend([38.04]).summary(resumeAt: 37), "38.0 °C. Charging resumes at 37 °C.")
        XCTAssertEqual(TempTrend().summary(resumeAt: 37), "Waiting for a temperature reading.")
    }

    func testKeepsOnlyThirtyMinutes() {
        var t = TempTrend()
        t.add(40, at: t0); t.add(39, at: t0 + 31 * 60)
        XCTAssertEqual(t.samples.count, 1)
        t.add(38, at: t0)   // clock moved back: older samples ahead of it are dropped
        XCTAssertEqual(t.samples.map(\.celsius), [38])
    }

    func testHeatSkippedWording() {
        let e = ChangeEvent.heatSkipped(percent: 8, limit: 40)
        XCTAssertEqual(e.title, "Charging despite the heat")
        XCTAssertEqual(e.category, .heat)
        XCTAssertTrue(e.body.contains("at 8%"))
    }

    func testStatusWithoutHeatSkippedDecodes() throws {
        let json = #"{"percent":50,"adapterOn":true,"state":{},"backend":"x"}"#
        XCTAssertNil(try JSONDecoder().decode(Status.self, from: Data(json.utf8)).heatSkipped)
    }
}
