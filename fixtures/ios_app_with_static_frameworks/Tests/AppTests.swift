import Foundation
import XCTest

@testable import App

final class AppTests: XCTestCase {
    func test_application() {
        XCTAssertEqual(App.AClassInThisBundle.value, "aValue")
    }
}
