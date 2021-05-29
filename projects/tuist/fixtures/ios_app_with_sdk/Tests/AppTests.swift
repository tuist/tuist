import Foundation
import XCTest
import MyTestFramework

@testable import App

final class AppTests: XCTestCase {
    private let helper = MyTestHelper()
    func test_foo() {
        helper.customAssert(true)
    }
}
