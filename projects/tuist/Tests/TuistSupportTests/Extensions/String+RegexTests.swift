import XCTest
@testable import TuistSupport

final class StringRegexTests: XCTestCase {
    func test_string_regex() {
        let osVersionPattern = "\\b[0-9]+\\.[0-9]+(?:\\.[0-9]+)?\\b"
        XCTAssertTrue("10.0.1".matches(pattern: osVersionPattern))
        XCTAssertFalse("tuist".matches(pattern: osVersionPattern))

        let twoDigitsOnlyPattern = "^[0-9]{2}$"
        XCTAssertTrue("10".matches(pattern: twoDigitsOnlyPattern))
        XCTAssertFalse("10.0.1".matches(pattern: twoDigitsOnlyPattern))

        let singleWordPattern = "project*"
        XCTAssertTrue("project".matches(pattern: singleWordPattern))
        XCTAssertFalse("This is a project".matches(pattern: singleWordPattern))
    }
}
