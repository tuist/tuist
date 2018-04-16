import Foundation
@testable import ProjectDescription
import XCTest

final class ConfigTests: XCTestCase {
    func test_toJSON_returns_the_right_value() {
        let subject = Config()
        let json = subject.toJSON()
        let expected = "{}"
        XCTAssertEqual(json.toString(), expected)
    }
}
