import XCTest
@testable import Framework4

class Framework4Tests: XCTestCase {
    func testHello() {
        let sut = Framework4File()

        XCTAssertEqual("Framework4File.hello()", sut.hello())
    }
}
