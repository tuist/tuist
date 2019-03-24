import Foundation
import XCTest
@testable import TuistKit

final class PlatformTests: XCTestCase {
    func test_xcodeSdkRoot_returns_the_right_value() {
        XCTAssertEqual(Platform.macOS.xcodeSdkRoot, "macosx")
        XCTAssertEqual(Platform.iOS.xcodeSdkRoot, "iphoneos")
        XCTAssertEqual(Platform.tvOS.xcodeSdkRoot, "appletvos")
//        XCTAssertEqual(Platform.watchOS.xcodeSdkRoot, "watchos")
    }

    func test_xcodeSupportedPLatforms_returns_the_right_value() {
        XCTAssertEqual(Platform.macOS.xcodeSupportedPlatforms, "macosx")
        XCTAssertEqual(Platform.iOS.xcodeSupportedPlatforms, "iphonesimulator iphoneos")
        XCTAssertEqual(Platform.tvOS.xcodeSupportedPlatforms, "appletvsimulator appletvos")
//        XCTAssertEqual(Platform.watchOS.xcodeSupportedPlatforms, "watchsimulator watchos")
    }

    func test_supportsLaunchScreen() {
        XCTAssertFalse(Platform.macOS.supportsLaunchScreen)
        XCTAssertTrue(Platform.iOS.supportsLaunchScreen)
        XCTAssertFalse(Platform.tvOS.supportsLaunchScreen)
//        XCTAssertFalse(Platform.watchOS.supportsLaunchScreen)
    }

    func test_mainStoryboardKey() {
        XCTAssertEqual(Platform.macOS.mainStoryboardKey, "NSMainStoryboardFile")
        XCTAssertEqual(Platform.iOS.mainStoryboardKey, "UIMainStoryboardFile")
        XCTAssertEqual(Platform.tvOS.mainStoryboardKey, "UIMainStoryboardFile")
//        XCTAssertEqual(Platform.watchOS.mainStoryboardKey, "UIMainStoryboardFile")
    }

    func test_launchScreenStoryboardKey() {
        XCTAssertNil(Platform.macOS.launchScreenStoryboardKey)
        XCTAssertEqual(Platform.iOS.launchScreenStoryboardKey, "UILaunchStoryboardName")
        XCTAssertNil(Platform.tvOS.launchScreenStoryboardKey)
//        XCTAssertNil(Platform.watchOS.launchScreenStoryboardKey)
    }
}
