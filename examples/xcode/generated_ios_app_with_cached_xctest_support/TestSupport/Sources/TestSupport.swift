import Foundation
import XCTest

public enum TestSupport {
    public static let expectedMessage = "cached-xctest-support"

    public static func assertMessage(_ message: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(message, expectedMessage, file: file, line: line)
    }
}
