import Foundation
import XCTest

@testable import A

final class ATests: XCTestCase {
    func test_value() {
        XCTAssertEqual(A.value, "aValue")
    }
}
