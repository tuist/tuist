import Foundation
import XCTest
import PrebuiltStaticFramework

@testable import App

final class AppTests: XCTestCase {
    func test_application() {
        XCTAssertEqual(StaticFrameworkClass().hello(), "StaticFrameworkClass.hello()")
        XCTAssertEqual(App.AClassInThisBundle.value, "aValue")
    }
}
