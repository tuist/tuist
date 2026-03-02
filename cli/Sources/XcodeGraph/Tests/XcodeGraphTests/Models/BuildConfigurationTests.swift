import Foundation
import XCTest
@testable import XcodeGraph

final class BuildConfigurationTests: XCTestCase {
    func test_codable() {
        // Given
        let subject = BuildConfiguration(
            name: "Debug",
            variant: .debug
        )

        // Then
        XCTAssertCodable(subject)
    }

    func test_name_returnsTheRightValue_whenDebug() {
        XCTAssertEqual(BuildConfiguration.debug.name, "Debug")
    }

    func test_name_returnsTheRightValue_whenRelease() {
        XCTAssertEqual(BuildConfiguration.release.name, "Release")
    }

    func test_hashValue() {
        XCTAssertEqual(
            BuildConfiguration(name: "Debug", variant: .debug).hashValue,
            BuildConfiguration(name: "Debug", variant: .debug).hashValue
        )
        XCTAssertEqual(
            BuildConfiguration(name: "Debug", variant: .debug).hashValue,
            BuildConfiguration.debug.hashValue
        )
        XCTAssertEqual(
            BuildConfiguration(name: "debug", variant: .debug).hashValue,
            BuildConfiguration.debug.hashValue
        )
        XCTAssertNotEqual(
            BuildConfiguration(name: "Debug", variant: .debug).hashValue,
            BuildConfiguration.release.hashValue
        )
        XCTAssertNotEqual(
            BuildConfiguration(name: "debug", variant: .debug).hashValue,
            BuildConfiguration.release.hashValue
        )
    }
}
