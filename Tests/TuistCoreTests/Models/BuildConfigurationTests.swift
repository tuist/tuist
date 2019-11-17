import Foundation
import XCTest
@testable import TuistCore

final class BuildConfigurationTests: XCTestCase {
    func test_name_returnsTheRightValue_whenDebug() {
        XCTAssertEqual(BuildConfiguration.debug.name, "Debug")
    }

    func test_name_returnsTheRightValue_whenRelease() {
        XCTAssertEqual(BuildConfiguration.release.name, "Release")
    }

    func test_xcodeValue_returnsTheRightValue_whenDebug() {
        XCTAssertEqual(BuildConfiguration.debug.xcodeValue, "Debug")
    }

    func test_xcodeValue_returnsTheRightValue_whenRelease() {
        XCTAssertEqual(BuildConfiguration.release.xcodeValue, "Release")
    }

    func test_equals() {
        XCTAssertEqual(BuildConfiguration(name: "Debug", variant: .debug),
                       BuildConfiguration(name: "Debug", variant: .debug))
        XCTAssertEqual(BuildConfiguration(name: "Debug", variant: .debug), .debug)
        XCTAssertEqual(BuildConfiguration(name: "debug", variant: .debug), .debug)
        XCTAssertNotEqual(BuildConfiguration(name: "Debug", variant: .debug), .release)
        XCTAssertNotEqual(BuildConfiguration(name: "debug", variant: .debug), .release)
    }

    func test_hashValue() {
        XCTAssertEqual(BuildConfiguration(name: "Debug", variant: .debug).hashValue,
                       BuildConfiguration(name: "Debug", variant: .debug).hashValue)
        XCTAssertEqual(BuildConfiguration(name: "Debug", variant: .debug).hashValue,
                       BuildConfiguration.debug.hashValue)
        XCTAssertEqual(BuildConfiguration(name: "debug", variant: .debug).hashValue,
                       BuildConfiguration.debug.hashValue)
        XCTAssertNotEqual(BuildConfiguration(name: "Debug", variant: .debug).hashValue,
                          BuildConfiguration.release.hashValue)
        XCTAssertNotEqual(BuildConfiguration(name: "debug", variant: .debug).hashValue,
                          BuildConfiguration.release.hashValue)
    }
}
