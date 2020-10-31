import Foundation
import XCTest

@testable import tvOSFramework

final class tvOSFrameworkTests: XCTestCase {
    func testHello() {
        let sut = tvOSFramework()
        
        XCTAssertEqual("tvOSFramework.hello()", sut.hello())
    }
}
