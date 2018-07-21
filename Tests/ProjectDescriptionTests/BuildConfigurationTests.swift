import Foundation
@testable import ProjectDescription
import XCTest

final class BuildConfigurationTests: XCTestCase {
    func test_toJSON_when_debug() {
        XCTAssertEqual(BuildConfiguration.debug.toJSON().toString(), "\"debug\"")
    }

    func test_toJSON_when_release() {
        XCTAssertEqual(BuildConfiguration.release.toJSON().toString(), "\"release\"")
    }
}
