import Foundation
import XCTest
@testable import xpmkit

final class BuildConfigurationTests: XCTestCase {
    func test_rawValue_returnsTheRightValue_whenDebug() {
        XCTAssertEqual(BuildConfiguration.debug.rawValue, "debug")
    }

    func test_rawValue_returnsTheRightValue_whenRelease() {
        XCTAssertEqual(BuildConfiguration.release.rawValue, "release")
    }

    func test_xcodeValue_returnsTheRightValue_whenDebug() {
        XCTAssertEqual(BuildConfiguration.debug.xcodeValue, "Debug")
    }

    func test_xcodeValue_returnsTheRightValue_whenRelease() {
        XCTAssertEqual(BuildConfiguration.release.xcodeValue, "Release")
    }
}
