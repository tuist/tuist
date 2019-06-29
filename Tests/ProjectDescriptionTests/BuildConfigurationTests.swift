import Foundation
import TuistCoreTesting
import XCTest

@testable import ProjectDescription

final class BuildConfigurationTests: XCTestCase {
    func test_toJSON_when_debug() {
        XCTAssertCodableEqualToJson([BuildConfiguration.debug], "[\"debug\"]")
    }

    func test_toJSON_when_release() {
        XCTAssertCodableEqualToJson([BuildConfiguration.release], "[\"release\"]")
    }
}
