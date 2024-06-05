import Foundation
import XCTest
@testable import XcodeGraph

final class PlatformTests: XCTestCase {
    func test_codable_iOS() {
        // Given
        let subject = Platform.iOS

        // Then
        XCTAssertCodable(subject)
    }

    func test_codable_tvOS() {
        // Given
        let subject = Platform.tvOS

        // Then
        XCTAssertCodable(subject)
    }

    func test_caseInsensitiveCommandInput() {
        XCTAssertEqual(Platform.macOS, Platform(commandLineValue: "macos"))
        XCTAssertEqual(Platform.macOS, Platform(commandLineValue: "macOS"))
        XCTAssertEqual(Platform.macOS, Platform(commandLineValue: "MACOS"))
        XCTAssertEqual(Platform.iOS, Platform(commandLineValue: "ios"))
        XCTAssertEqual(Platform.iOS, Platform(commandLineValue: "iOS"))
        XCTAssertEqual(Platform.iOS, Platform(commandLineValue: "IOS"))
        XCTAssertEqual(Platform.tvOS, Platform(commandLineValue: "tvos"))
        XCTAssertEqual(Platform.tvOS, Platform(commandLineValue: "tvOS"))
        XCTAssertEqual(Platform.watchOS, Platform(commandLineValue: "watchos"))
        XCTAssertEqual(Platform.watchOS, Platform(commandLineValue: "watchOS"))
        XCTAssertEqual(Platform.visionOS, Platform(commandLineValue: "visionos"))
        XCTAssertEqual(Platform.visionOS, Platform(commandLineValue: "visionOS"))
    }

    func test_caseInvalidPlatform_throws() {
        do {
            let _ = try Platform.from(commandLineValue: "not_a_platform")
            XCTFail("Expected erro to be thrown")
        } catch let error as UnsupportedPlatformError {
            XCTAssertEqual(error, UnsupportedPlatformError(input: "not_a_platform"))
        } catch {
            XCTFail("Unexpected error thrown")
        }
    }

    func test_caseValidPlatform_doesNotThrow() throws {
        XCTAssertEqual(Platform.iOS, try Platform.from(commandLineValue: "iOS"))
        XCTAssertEqual(Platform.macOS, try Platform.from(commandLineValue: "macOS"))
        XCTAssertEqual(Platform.macOS, try Platform.from(commandLineValue: "macos"))
    }

    func test_xcodeSdkRoot_returns_the_right_value() {
        XCTAssertEqual(Platform.macOS.xcodeSdkRoot, "macosx")
        XCTAssertEqual(Platform.iOS.xcodeSdkRoot, "iphoneos")
        XCTAssertEqual(Platform.tvOS.xcodeSdkRoot, "appletvos")
        XCTAssertEqual(Platform.watchOS.xcodeSdkRoot, "watchos")
        XCTAssertEqual(Platform.visionOS.xcodeSdkRoot, "xros")
    }

    func test_xcodeSimulatorSDK() {
        XCTAssertEqual(Platform.tvOS.xcodeSimulatorSDK, "appletvsimulator")
        XCTAssertEqual(Platform.iOS.xcodeSimulatorSDK, "iphonesimulator")
        XCTAssertEqual(Platform.watchOS.xcodeSimulatorSDK, "watchsimulator")
        XCTAssertEqual(Platform.visionOS.xcodeSimulatorSDK, "xrsimulator")
        XCTAssertNil(Platform.macOS.xcodeSimulatorSDK)
    }

    func test_xcodeDeviceSDK() {
        XCTAssertEqual(Platform.tvOS.xcodeDeviceSDK, "appletvos")
        XCTAssertEqual(Platform.iOS.xcodeDeviceSDK, "iphoneos")
        XCTAssertEqual(Platform.watchOS.xcodeDeviceSDK, "watchos")
        XCTAssertEqual(Platform.macOS.xcodeDeviceSDK, "macosx")
        XCTAssertEqual(Platform.visionOS.xcodeDeviceSDK, "xros")
    }

    func test_hasSimulators() {
        XCTAssertFalse(Platform.macOS.hasSimulators)
        XCTAssertTrue(Platform.tvOS.hasSimulators)
        XCTAssertTrue(Platform.watchOS.hasSimulators)
        XCTAssertTrue(Platform.tvOS.hasSimulators)
        XCTAssertTrue(Platform.visionOS.hasSimulators)
    }

    func test_xcodeSdkRootPath() {
        // Given
        let platforms: [Platform] = [
            .iOS,
            .macOS,
            .tvOS,
            .watchOS,
            .visionOS,
        ]

        // When
        let paths = platforms.map(\.xcodeSdkRootPath)

        // Then
        XCTAssertEqual(paths, [
            "Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk",
            "Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk",
            "Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk",
            "Platforms/WatchOS.platform/Developer/SDKs/WatchOS.sdk",
            "Platforms/XROS.platform/Developer/SDKs/XROS.sdk",
        ])
    }
}
