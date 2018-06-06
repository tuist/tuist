import Foundation
@testable import ProjectDescription
import XCTest

final class PlatformTests: XCTestCase {
    func test_toJSON_returns_the_right_value() {
        XCTAssertEqual(Platform.iOS.toJSON().toString(), "\"iOS\"")
        XCTAssertEqual(Platform.macOS.toJSON().toString(), "\"macOS\"")
        XCTAssertEqual(Platform.watchOS.toJSON().toString(), "\"watchOS\"")
        XCTAssertEqual(Platform.tvOS.toJSON().toString(), "\"tvOS\"")
    }
}
