import Foundation
import XCTest

@testable import App

final class AppTests: XCTestCase {
    func testHello() {
        let sut = App()

        XCTAssertEqual("App.hello()", sut.hello())
    }
}
