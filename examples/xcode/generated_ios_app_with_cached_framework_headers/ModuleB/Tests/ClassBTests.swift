import XCTest
@testable import ModuleB

class ClassBTests: XCTestCase {
    func testHello() {
        let sut = ClassB()
        XCTAssertEqual("ClassB.hello -> ClassA.hello", sut.hello())
    }
}
