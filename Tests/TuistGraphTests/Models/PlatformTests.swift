import Foundation
import XCTest
@testable import TuistGraph

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

    func test_carthageDirectory() {
        XCTAssertEqual(Platform.tvOS.carthageDirectory, "tvOS")
        XCTAssertEqual(Platform.iOS.carthageDirectory, "iOS")
        XCTAssertEqual(Platform.watchOS.carthageDirectory, "watchOS")
        XCTAssertEqual(Platform.macOS.carthageDirectory, "Mac")
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
