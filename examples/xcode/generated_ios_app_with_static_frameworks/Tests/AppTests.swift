import A
import AppTestsSupport
import Foundation
import PrebuiltStaticFramework
import XCTest

@testable import App

final class AppTests: XCTestCase {
    func test_application() {
        XCTAssertEqual(App.AClassInThisBundle.value, "aValue")
        XCTAssertEqual(A.value, "aValue")
        XCTAssertEqual(StaticFrameworkClass().hello(), "StaticFrameworkClass.hello()")
        XCTAssertEqual(AppTestsSupport.value, "appTestsSupportValue")
    }
}
