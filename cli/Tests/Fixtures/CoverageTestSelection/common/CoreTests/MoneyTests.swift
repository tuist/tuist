import Core
import Foundation
import XCTest

final class MoneyTests: XCTestCase {
    func testFormatsDollars() {
        XCTAssertEqual(Money(cents: 1234).formatted, "$12.34")
    }

    func testAddsAmounts() {
        // The scenario script records the failed-at-baseline run with
        // TEST_RUNNER_TESTBED_FAILING_TESTS=MoneyTests/testAddsAmounts.
        let failing = ProcessInfo.processInfo.environment["TESTBED_FAILING_TESTS"] ?? ""
        if failing.split(separator: ",").contains("MoneyTests/testAddsAmounts") {
            XCTFail("Failing on request")
        }
        XCTAssertEqual(Money(cents: 250) + Money(cents: 105), Money(cents: 355))
    }
}
