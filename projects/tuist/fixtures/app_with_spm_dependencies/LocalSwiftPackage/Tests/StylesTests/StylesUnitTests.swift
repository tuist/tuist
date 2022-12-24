import Foundation
import TestsSupport
import XCTest
@testable import Styles

final class StylesUnitTests: XCTestCase {
    func testSupportImport() {
        XCTPass()
    }

    func testStyles() {
        XCTAssertEqual(Styles.Color.blue, Styles.Color.blue)
    }

    func testJson() {
        let json = "{name: \"tuist\"}"
        testJson(json, record: false)
    }
}
