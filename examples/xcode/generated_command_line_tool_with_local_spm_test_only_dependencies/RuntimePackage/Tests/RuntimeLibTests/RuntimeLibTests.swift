import RuntimeLib
import TestSupport
import XCTest

final class RuntimeLibTests: XCTestCase {
    func testMessage() {
        XCTAssertEqual(RuntimeLib().message, TestSupport.expectedMessage)
    }
}
