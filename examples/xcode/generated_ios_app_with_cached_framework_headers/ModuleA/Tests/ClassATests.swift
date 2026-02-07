import XCTest
@testable import ModuleA

class ClassATests: XCTestCase {
    func testHello() {
        let sut = ClassA()
        XCTAssertEqual("ClassA.hello", sut.hello())
    }
}
