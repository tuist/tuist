import XCTest
@testable import Framework3

class Framework3Tests: XCTestCase {
    func testHello() {
        let sut = Framework3File()

        XCTAssertEqual("Framework3File.hello()", sut.hello())
    }
}
