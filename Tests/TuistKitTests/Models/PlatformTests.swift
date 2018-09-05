import Foundation
@testable import TuistKit
import XCTest

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
}
