import Foundation
@testable import xcbuddykit
import XCTest

final class AppTests: XCTestCase {
    var subject: App!

    override func setUp() {
        super.setUp()
        subject = App(infoDictionary: [
            "CFBundleShortVersionString": "3.0.0",
        ])
    }

    func test_version_returns_the_right_value() {
        XCTAssertEqual(subject.version, "3.0.0")
    }
}
