import Foundation
@testable import xcbuddykit
import XCTest

final class PlatformTests: XCTestCase {
    func test_xcodeSdkRoot_returns_the_right_value() {
        XCTAssertEqual(Platform.macos.xcodeSdkRoot, "macosx")
        XCTAssertEqual(Platform.ios.xcodeSdkRoot, "iphoneos")
        XCTAssertEqual(Platform.tvos.xcodeSdkRoot, "appletvos")
        XCTAssertEqual(Platform.watchos.xcodeSdkRoot, "watchos")
    }

    func test_xcodeSupportedPLatforms_returns_the_right_value() {
        XCTAssertEqual(Platform.macos.xcodeSupportedPlatforms, "macosx")
        XCTAssertEqual(Platform.ios.xcodeSupportedPlatforms, "iphonesimulator iphoneos")
        XCTAssertEqual(Platform.tvos.xcodeSupportedPlatforms, "appletvsimulator appletvos")
        XCTAssertEqual(Platform.watchos.xcodeSupportedPlatforms, "watchsimulator watchos")
    }
}
