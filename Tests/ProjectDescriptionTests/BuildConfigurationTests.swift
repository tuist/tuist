import Foundation
import XCTest
@testable import ProjectDescription

final class BuildConfigurationTests: XCTestCase {
    func test_toJSON_when_debug() {
        assertCodableEqualToJson([BuildConfiguration.debug], "[\"debug\"]")
    }

    func test_toJSON_when_release() {
        assertCodableEqualToJson([BuildConfiguration.release], "[\"release\"]")
    }
}
