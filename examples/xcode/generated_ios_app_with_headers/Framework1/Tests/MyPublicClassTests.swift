import XCTest
@testable import Framework1

class MyPublicClassTests: XCTestCase {
    func testHello() {
        let sut = MyPublicClass()

        XCTAssertEqual("MyPublicClass.hello", sut.hello())
    }
}
