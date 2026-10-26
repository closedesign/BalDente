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

final class PanelHeightRuleTests: XCTestCase {
    func testCapsOnTallScreens() { XCTAssertEqual(PanelHeightRule.maxHeight(screen: 1400), 520) }
    func testShortScreensKeepMargin() { XCTAssertEqual(PanelHeightRule.maxHeight(screen: 500), 460) }
    func testNeverTiny() { XCTAssertEqual(PanelHeightRule.maxHeight(screen: 100), 200) }
    func testHiddenBelow() {
        XCTAssertEqual(PanelHeightRule.hiddenBelow(contentHeight: 900, offset: 0, visibleHeight: 480), 420)
        XCTAssertEqual(PanelHeightRule.hiddenBelow(contentHeight: 900, offset: 430, visibleHeight: 480), 0)
        XCTAssertEqual(PanelHeightRule.hiddenBelow(contentHeight: 300, offset: 0, visibleHeight: 480), 0)
    }
    func testHint() {
        XCTAssertTrue(PanelHeightRule.showsMoreHint(hiddenBelow: 100))
        XCTAssertFalse(PanelHeightRule.showsMoreHint(hiddenBelow: 5))
    }
}
