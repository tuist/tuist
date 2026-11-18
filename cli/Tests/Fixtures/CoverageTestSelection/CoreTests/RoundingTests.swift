import Core
import XCTest

final class RoundingTests: XCTestCase {
    func testRoundsDownToWholeCents() {
        XCTAssertEqual(Discount.apply(percent: 15, to: Prices.cents(333)), Money(cents: 283))
    }
}
