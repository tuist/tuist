import XCTest

final class FlakyHackdayTests: XCTestCase {
    func testRandomlyFailsHalfTheTime() {
        XCTAssertTrue(Bool.random(), "Intentional hackday flaky test")
    }
}
