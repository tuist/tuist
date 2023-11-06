import XCTest
@testable import App

class AppDelegateTests: XCTestCase {
    func testHello() {
        let sut = AppDelegate()

        XCTAssertEqual("AppDelegate.hello()", sut.hello())
    }
}
