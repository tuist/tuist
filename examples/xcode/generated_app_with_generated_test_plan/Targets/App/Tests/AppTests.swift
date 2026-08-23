import Foundation
import XCTest

final class AppTests: XCTestCase {
    func test_selected() {
        XCTAssertEqual(2 + 2, 4)
    }

    func test_skipped() {
        XCTFail("The generated test plan must skip this test")
    }
}
