import XCTest
@testable import Framework2

class MyPublicClassTests: XCTestCase {
    func testHello() {
        let sut = MyPublicClass()

        XCTAssertEqual("MyPublicClass.hello", sut.hello())
    }
}
