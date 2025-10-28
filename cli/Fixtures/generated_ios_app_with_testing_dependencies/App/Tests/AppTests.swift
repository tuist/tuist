import AppTesting
import Testing
import XCTest

class AppTestsXCTest: XCTestCase {
    func test() {
        XCTAssertCustom()
    }
}

struct AppTestsSwiftTesting {
    @Test func test() {
        customExpect()
    }
}
