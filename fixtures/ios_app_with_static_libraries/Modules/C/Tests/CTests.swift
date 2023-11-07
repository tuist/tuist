import Foundation
import XCTest

@testable import C

final class BTests: XCTestCase {
    func test_value() {
        XCTAssertEqual(C.value, "cValue")
    }
}
