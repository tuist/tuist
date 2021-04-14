import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class PresetBuildConfigurationTests: XCTestCase {
    func test_preset_names() {
        XCTAssertEqual(PresetBuildConfiguration.debug.name, "Debug")
        XCTAssertEqual(PresetBuildConfiguration.release.name, "Release")
    }
}
