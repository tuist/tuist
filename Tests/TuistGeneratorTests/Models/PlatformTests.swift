import Foundation
import XCTest
@testable import TuistGenerator

final class PlatformTests: XCTestCase {
    func test_xcodeSdkRoot_returns_the_right_value() {
        XCTAssertEqual(Platform.macOS.xcodeSdkRoot, "macosx")
        XCTAssertEqual(Platform.iOS.xcodeSdkRoot, "iphoneos")
        XCTAssertEqual(Platform.tvOS.xcodeSdkRoot, "appletvos")
    }

    func test_xcodeSupportedPLatforms_returns_the_right_value() {
        XCTAssertEqual(Platform.macOS.xcodeSupportedPlatforms, ["macosx"])
        XCTAssertEqual(Platform.iOS.xcodeSupportedPlatforms, ["iphonesimulator", "iphoneos"])
        XCTAssertEqual(Platform.tvOS.xcodeSupportedPlatforms, ["appletvsimulator", "appletvos"])
    }

    func test_xcodeSdkRootPath() {
        // Given
        let platforms: [Platform] = [
            .iOS,
            .macOS,
            .tvOS,
        ]

        // When
        let paths = platforms.map(\.xcodeSdkRootPath)

        // Then
        XCTAssertEqual(paths, [
            "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk",
            "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk",
            "Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk",
        ])
    }
}
