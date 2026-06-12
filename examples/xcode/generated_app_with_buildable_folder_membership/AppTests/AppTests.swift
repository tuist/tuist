import XCTest

final class AppTests: XCTestCase {
    func testSharedStub() {
        XCTAssertEqual(SharedStub.value, 42)
    }
}
