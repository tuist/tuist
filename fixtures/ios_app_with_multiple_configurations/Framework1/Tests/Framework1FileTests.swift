@testable import Framework1
import XCTest

class Framework1Tests: XCTestCase {

   func testHello() {
       let sut = Framework1File()

       XCTAssertEqual("Framework1File.hello()", sut.hello())
   }

   func testHelloFromFramework2() {
       let sut = Framework1File()

       XCTAssertEqual("Framework1File -> Framework2File.hello()", sut.helloFromFramework2())
   }
}
