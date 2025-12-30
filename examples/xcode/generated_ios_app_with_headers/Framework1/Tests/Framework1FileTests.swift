import XCTest
@testable import Framework1

class Framework1Tests: XCTestCase {
    func testHello() {
        let sut = Framework1File()

        XCTAssertEqual("Framework1File.hello()", sut.hello())
    }
}
