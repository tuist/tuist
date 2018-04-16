import Foundation
@testable import ProjectDescription
import XCTest

final class BuildConfigurationTests: XCTestCase {
    func test_toJSON_returns_the_right_value_when_debug() {
        XCTAssertEqual(BuildConfiguration.debug.toJSON().toString(), "\"debug\"")
    }

    func test_toJSON_returns_the_right_value_when_release() {
        XCTAssertEqual(BuildConfiguration.release.toJSON().toString(), "\"release\"")
    }
}
