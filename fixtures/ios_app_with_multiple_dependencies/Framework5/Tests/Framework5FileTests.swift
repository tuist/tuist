import XCTest
@testable import Framework5

class Framework5Tests: XCTestCase {
    func testHello() {
        let sut = Framework5File()

        XCTAssertEqual("Framework5File.hello()", sut.hello())
    }
}
