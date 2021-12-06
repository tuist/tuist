import XCTest
@testable import StaticFramework1

class Framework1Tests: XCTestCase {
    func testHello() {
        let sut = Framework1File()

        XCTAssertEqual("Framework1File.hello()", sut.hello())
    }

    #if canImport(Framework2)
        func testHelloFromFramework2() {
            let sut = Framework1File()

            XCTAssertEqual("Framework1File -> Framework2File.hello()", sut.helloFromFramework2())
        }
    #endif
}
