import Calculator
import XCTest

final class CalculatorTests: XCTestCase {
    func test_add() {
        XCTAssertEqual(Calculator.add(1, 2), 3)
    }
}
