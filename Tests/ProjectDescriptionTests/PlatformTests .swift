import Foundation
@testable import ProjectDescription
import XCTest

final class PlatformTests: XCTestCase {
    func test_toJSON_returns_the_right_value() {
        XCTAssertEqual(Platform.ios.toJSON().toString(), "\"ios\"")
        XCTAssertEqual(Platform.macos.toJSON().toString(), "\"macos\"")
        XCTAssertEqual(Platform.watchos.toJSON().toString(), "\"watchos\"")
        XCTAssertEqual(Platform.tvos.toJSON().toString(), "\"tvos\"")
    }
}
