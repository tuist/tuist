import Foundation
@testable import ProjectDescription
import XCTest

final class PlatformTests: XCTestCase {
    func test_toJSON_returns_the_right_value() {
        XCTAssertEqual(Platform.iOS.toJSON().toString(), "\"ios\"")
        XCTAssertEqual(Platform.macOS.toJSON().toString(), "\"macos\"")
        XCTAssertEqual(Platform.watchOS.toJSON().toString(), "\"watchos\"")
        XCTAssertEqual(Platform.tvOS.toJSON().toString(), "\"tvos\"")
    }
}
