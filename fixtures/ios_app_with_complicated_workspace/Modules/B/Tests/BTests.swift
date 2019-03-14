import Foundation
import XCTest

@testable import B

final class BTests: XCTestCase {
    func test_value() {
        XCTAssertEqual(B.value, "bValue")
    }
}
