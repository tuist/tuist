import Foundation
import XCTest

@testable import tvOSFramework

final class TVOSFrameworkTests: XCTestCase {
    func testHello() {
        let sut = tvOSFramework()

        XCTAssertEqual("tvOSFramework.hello()", sut.hello())
    }
}
