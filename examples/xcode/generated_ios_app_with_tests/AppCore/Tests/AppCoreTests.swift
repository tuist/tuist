import Foundation
import XCTest

@testable import AppCore

final class AppCoreTests: XCTestCase {
    func testHello() {
        let sut = AppCore()

        XCTAssertEqual("AppCore.hello()", sut.hello())
    }
}
