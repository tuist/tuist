import Foundation
import XCTest

@testable import App

final class AppTests: XCTestCase {
    func testHello() {
        let sut = AppDelegate()

        XCTAssertEqual("AppDelegate.hello()", sut.hello())
    }
}
