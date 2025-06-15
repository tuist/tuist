import XCTest
@testable import FrameworkA

class FrameworkATest: XCTestCase {
    func testProperty() async throws {
        XCTAssertEqual(FrameworkA.text, "Hello, FrameworkA!")
    }
}
