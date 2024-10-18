import Testing
import XCTest

@testable import App

final class MyAppTests: XCTestCase {
    func testHello() {
        let sut = MyApp()

        XCTAssertEqual("MyApp.hello()", sut.hello())
    }
}

@Suite struct MyAppSwiftTests {
    @Test func testHello() {
        let sut = MyApp()

        #expect(sut.hello() == "MyApp.hello()")
    }
}
