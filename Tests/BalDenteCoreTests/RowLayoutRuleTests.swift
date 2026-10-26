import XCTest
@testable import BalDenteCore

final class RowLayoutRuleTests: XCTestCase {
    func testWideRowStaysSideBySide() {
        XCTAssertFalse(RowLayoutRule.stacked(width: 700, controlWidth: 230, minLead: 230, gap: 12))
    }
    func testNarrowRowStacks() {
        XCTAssertTrue(RowLayoutRule.stacked(width: 400, controlWidth: 230, minLead: 230, gap: 12))
    }
    func testExactFitStaysSideBySideAndInfiniteNeverStacks() {
        XCTAssertFalse(RowLayoutRule.stacked(width: 472, controlWidth: 230, minLead: 230, gap: 12))
        XCTAssertFalse(RowLayoutRule.stacked(width: .infinity, controlWidth: 900, minLead: 230, gap: 12))
    }
}

final class AppearanceStyleTests: XCTestCase {
    func testOldConfigWithoutStyleDecodesToAurora() throws {
        let a = try JSONDecoder().decode(Appearance.self, from: Data(#"{"mode":"preset","preset":"Ocean"}"#.utf8))
        XCTAssertEqual(a.style, "aurora")
        XCTAssertEqual(a.theme, "dark")
        XCTAssertEqual(a.preset, "Ocean")
    }
}

final class ColumnRuleTests: XCTestCase {
    func testColumnsGrowWithWidthUpToThree() {
        XCTAssertEqual(ColumnRule.count(width: 300, minColumn: 380, spacing: 18), 1)
        XCTAssertEqual(ColumnRule.count(width: 800, minColumn: 380, spacing: 18), 2)
        XCTAssertEqual(ColumnRule.count(width: 1200, minColumn: 380, spacing: 18), 3)
        XCTAssertEqual(ColumnRule.count(width: 3000, minColumn: 380, spacing: 18), 3)
        XCTAssertEqual(ColumnRule.count(width: .infinity, minColumn: 380, spacing: 18), 1)
    }
}
