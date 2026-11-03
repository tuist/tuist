import Core
import XCTest

final class DiscountTests: XCTestCase {
    func testTenPercentOff() {
        XCTAssertEqual(Discount.apply(percent: 10, to: Money(cents: 1000)), Money(cents: 900))
    }

    func testZeroPercentKeepsPrice() {
        XCTAssertEqual(Discount.apply(percent: 0, to: Prices.tenDollars()), Prices.tenDollars())
    }
}
