import Foundation
import TuistSupportTesting
import XCTest

@testable import ProjectDescription

final class PresetBuildConfigurationTests: XCTestCase {
    func test_preset_names() {
        XCTAssertEqual(PresetBuildConfiguration.debug.name, "Debug")
        XCTAssertEqual(PresetBuildConfiguration.release.name, "Release")
        XCTAssertEqual(PresetBuildConfiguration.custom("Beta").name, "Beta")
    }

    func test_codable() {
        XCTAssertCodable(PresetBuildConfiguration.debug)
        XCTAssertCodable(PresetBuildConfiguration.release)
        XCTAssertCodable(PresetBuildConfiguration.custom("Beta"))
    }
}
