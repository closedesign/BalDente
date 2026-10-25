import XCTest
@testable import BalDenteCore

final class SettingsSearchTests: XCTestCase {
    private let items = [
        SettingsItem("Heat protection", "Pause charging when the battery is hot.", keywords: ["temperature", "thermal"], page: "Charging"),
        SettingsItem("Menu bar charging effect", "Animate the charging highlight.", keywords: ["animation"], page: "Battery"),
        SettingsItem("Use Wi-Fi icon for Ethernet", page: "Network"),
        SettingsItem("Launch at login", "Start BalDente automatically.", keywords: ["startup"], page: "General"),
    ]

    func testEmptyQueryMatchesNothing() {
        XCTAssertTrue(SettingsSearch.rank(items, query: "").isEmpty)
        XCTAssertTrue(SettingsSearch.rank(items, query: "   ").isEmpty)
    }

    func testMatchesTitleKeywordAndDetail() {
        XCTAssertEqual(SettingsSearch.rank(items, query: "heat").first?.title, "Heat protection")
        XCTAssertEqual(SettingsSearch.rank(items, query: "thermal").map(\.title), ["Heat protection"])
        XCTAssertEqual(SettingsSearch.rank(items, query: "highlight").map(\.title), ["Menu bar charging effect"])
        XCTAssertEqual(SettingsSearch.rank(items, query: "animation").map(\.title), ["Menu bar charging effect"])
    }

    func testIgnoresCaseAndHyphens() {
        XCTAssertEqual(SettingsSearch.rank(items, query: "WIFI").map(\.title), ["Use Wi-Fi icon for Ethernet"])
        XCTAssertEqual(SettingsSearch.rank(items, query: "wi-fi").map(\.title), ["Use Wi-Fi icon for Ethernet"])
    }

    func testEveryWordMustMatch() {
        XCTAssertEqual(SettingsSearch.rank(items, query: "charging effect").map(\.title), ["Menu bar charging effect"])
        XCTAssertTrue(SettingsSearch.rank(items, query: "charging nonsense").isEmpty)
    }

    func testTitleBeatsDescription() {
        // "charging" is in Heat protection's description but in the other item's title.
        XCTAssertEqual(SettingsSearch.rank(items, query: "charging").map(\.title), ["Menu bar charging effect", "Heat protection"])
    }

    func testPageNameIsSearchable() {
        XCTAssertEqual(SettingsSearch.rank(items, query: "network").map(\.title), ["Use Wi-Fi icon for Ethernet"])
    }

    func testUniqueZoneName() {
        XCTAssertEqual(uniqueZoneName("New Zone", existing: ["Home"]), "New Zone")
        XCTAssertEqual(uniqueZoneName("New Zone", existing: ["Home", "New Zone"]), "New Zone 2")
        XCTAssertEqual(uniqueZoneName("New Zone", existing: ["new zone", "New Zone 2"]), "New Zone 3")
    }
}
