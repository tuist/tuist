import Foundation
@testable import ProjectDescription
import XCTest

final class BuildConfigurationTests: XCTestCase {
    func test_toJSON_when_debug() {
        assertCodableEqualToJson([BuildConfiguration.debug], "[\"debug\"]")
    }

    func test_toJSON_when_release() {
        assertCodableEqualToJson([BuildConfiguration.release], "[\"release\"]")
    }
}
