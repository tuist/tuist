import XCTest
@testable import ModuleB

class ModuleBFileTests: XCTestCase {
    func testHello() {
        let sut = ModuleBFile()
        XCTAssertEqual("ModuleBFile.hello() -> ClassA.hello", sut.hello())
    }
}
