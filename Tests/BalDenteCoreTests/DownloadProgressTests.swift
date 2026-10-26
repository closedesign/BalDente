import XCTest
@testable import BalDenteCore

final class DownloadProgressTests: XCTestCase {
    func testFractionAndLabel() {
        let p = DownloadProgress(written: 20_000_000, total: 40_000_000, elapsed: 10)
        XCTAssertEqual(p.fraction, 0.5)
        XCTAssertEqual(p.label, "50% · 20.0 MB of 40.0 MB · 2.0 MB/s")
    }
    func testUnknownTotalHasNoFractionOrPercent() {
        let p = DownloadProgress(written: 500_000, total: -1, elapsed: 0.1)
        XCTAssertNil(p.fraction)
        XCTAssertNil(p.bytesPerSecond)
        XCTAssertEqual(p.label, "500 KB")
    }
    func testFractionNeverExceedsOne() {
        XCTAssertEqual(DownloadProgress(written: 9, total: 5, elapsed: 1).fraction, 1)
    }
}
