import Foundation
import XCTest

@testable import C

final class CTests: XCTestCase {
    func test_value() {
        XCTAssertEqual(C.value, "cValue")
    }
}
