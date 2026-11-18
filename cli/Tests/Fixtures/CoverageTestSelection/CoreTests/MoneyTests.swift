import Core
import XCTest

final class MoneyTests: XCTestCase {
    func testFormatsDollars() {
        XCTAssertEqual(Money(cents: 1234).formatted, "$12.34")
    }

    func testAddsAmounts() {
        XCTAssertEqual(Money(cents: 250) + Money(cents: 105), Money(cents: 355))
    }
}
