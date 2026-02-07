import XCTest
@testable import ModuleA

class ModuleAFileTests: XCTestCase {
    func testHello() {
        let sut = ModuleAFile()
        XCTAssertEqual("ModuleAFile.hello()", sut.hello())
    }
}
