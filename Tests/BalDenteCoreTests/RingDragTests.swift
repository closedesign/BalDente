@testable import BalDenteCore
import XCTest

final class RingDragTests: XCTestCase {
    func testPercentFromAngle() {
        XCTAssertEqual(RingDrag.percent(dx: 0, dy: -10, previous: 10), 0)    // 12 o'clock
        XCTAssertEqual(RingDrag.percent(dx: 10, dy: 0, previous: 30), 25)    // 3 o'clock
        XCTAssertEqual(RingDrag.percent(dx: 0, dy: 10, previous: 50), 50)    // 6 o'clock
        XCTAssertEqual(RingDrag.percent(dx: -10, dy: 0, previous: 70), 75)   // 9 o'clock
    }

    func testPercentDoesNotWrapAcrossTop() {
        // Just past 12 o'clock while dragging up from 98 stays at 100, not 1.
        XCTAssertEqual(RingDrag.percent(dx: 0.3, dy: -10, previous: 98), 100)
        // Just before 12 o'clock while near 0 stays at 0, not 99.
        XCTAssertEqual(RingDrag.percent(dx: -0.3, dy: -10, previous: 3), 0)
    }

    func testHandlePicksNearest() {
        XCTAssertEqual(RingDrag.handle(at: 79, upper: 80, lower: 60), .upper)
        XCTAssertEqual(RingDrag.handle(at: 62, upper: 80, lower: 60), .lower)
        // Adjacent markers: the side of the touch decides.
        XCTAssertEqual(RingDrag.handle(at: 81, upper: 80, lower: 79), .upper)
        XCTAssertEqual(RingDrag.handle(at: 78, upper: 80, lower: 79), .lower)
        // A limit of 100% sits at 12 o'clock, so a touch just past the top (1%) is next to it.
        XCTAssertEqual(RingDrag.handle(at: 1, upper: 100, lower: 60), .upper)
        XCTAssertEqual(RingDrag.distance(1, 100), 1)
    }

    func testCloseMarkersPickByDirection() {
        XCTAssertNil(RingDrag.handle(start: 49, now: 49, upper: 50, lower: 48))
        XCTAssertEqual(RingDrag.handle(start: 49, now: 52, upper: 50, lower: 48), .upper)
        XCTAssertEqual(RingDrag.handle(start: 49, now: 46, upper: 50, lower: 48), .lower)
        // Far apart: the press point decides at once.
        XCTAssertEqual(RingDrag.handle(start: 79, now: 79, upper: 80, lower: 60), .upper)
    }

    func testMoveClampsAndPushes() {
        XCTAssertEqual(RingDrag.move(.upper, to: 90, upper: 80, lower: 75).upper, 90)
        XCTAssertEqual(RingDrag.move(.upper, to: 90, upper: 80, lower: 75).lower, 75)
        // Limit dragged below resume pushes resume down.
        let a = RingDrag.move(.upper, to: 50, upper: 80, lower: 75)
        XCTAssertEqual(a.upper, 50); XCTAssertEqual(a.lower, 49)
        // Resume dragged above the limit pushes the limit up.
        let b = RingDrag.move(.lower, to: 85, upper: 80, lower: 75)
        XCTAssertEqual(b.upper, 86); XCTAssertEqual(b.lower, 85)
        // Ranges match the zone editor.
        XCTAssertEqual(RingDrag.move(.upper, to: 3, upper: 80, lower: 75).upper, 20)
        XCTAssertEqual(RingDrag.move(.lower, to: 100, upper: 80, lower: 75).lower, 99)
        XCTAssertEqual(RingDrag.move(.lower, to: 100, upper: 80, lower: 75).upper, 100)
        XCTAssertEqual(RingDrag.move(.lower, to: 0, upper: 80, lower: 75).lower, 5)
    }
}
