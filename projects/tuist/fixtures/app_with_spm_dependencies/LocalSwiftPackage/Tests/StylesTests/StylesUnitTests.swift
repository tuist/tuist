import Foundation
import TestsSupport
@testable import Styles
import XCTest

final class StylesUnitTests: XCTestCase {
    func testSupportImport() {
        XCTAssertEqual(getSomething(), "Something")
    }
    
    func testStyles() {
        XCTAssertEqual(Styles.Color.blue, Styles.Color.blue)
    }
}
