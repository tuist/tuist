@testable import App
import XCTest

class AppDelegateTests: XCTestCase {
    func testHello() {
        let sut = AppDelegate()

        XCTAssertEqual("AppDelegate.hello()", sut.hello())
    }
}
