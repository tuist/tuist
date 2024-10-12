import XCTest

@testable import App

class MyAppTests: XCTestCase {
    func testHello() {
        let sut = MyApp()

        XCTAssertEqual("MyApp.hello()", sut.hello())
    }
}
