import Foundation
import TSCBasic
import XCTest

import TuistSupportTesting
@testable import TuistCore

final class SDKNodeTests: XCTestCase {
    func test_frameworkSearchPath() throws {
        XCTAssertEqual(SDKSource.developer.frameworkSearchPath, "$(DEVELOPER_FRAMEWORKS_DIR)")
        XCTAssertEqual(SDKSource.system.frameworkSearchPath, "$(PLATFORM_DIR)/Developer/Library/Frameworks")
    }

    func test_sdk_supportedTypes() throws {
        // Given
        let libraries = [
            "Foo.framework",
            "libBar.tbd",
        ]

        // When / Then
        XCTAssertNoThrow(try libraries.map { try SDKNode(name: $0, platform: .macOS, status: .required, source: .developer) })
    }

    func test_sdk_usupportedTypes() throws {
        XCTAssertThrowsSpecific(try SDKNode(name: "FooBar", platform: .tvOS, status: .required, source: .developer),
                                SDKNode.Error.unsupported(sdk: "FooBar"))
    }

    func test_sdk_errors() {
        XCTAssertEqual(SDKNode.Error.unsupported(sdk: "Foo").type, .abort)
    }

    func test_sdk_framework_paths() throws {
        // Given
        let libraries: [(name: String, platform: Platform)] = [
            ("Foo.framework", .iOS),
            ("Bar.framework", .macOS),
            ("FooBar.framework", .tvOS),
        ]

        // When
        let nodes = try libraries.map { try SDKNode(name: $0.name, platform: $0.platform, status: .required, source: .developer) }

        // Then
        XCTAssertEqual(nodes.map(\.path), [
            "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/Foo.framework",
            "/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Bar.framework",
            "/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/System/Library/Frameworks/FooBar.framework",
        ])
    }

    func test_xctest_sdk_framework_path() throws {
        // Given
        let libraries: [(name: String, platform: Platform)] = [
            ("XCTest.framework", .iOS),
            ("XCTest.framework", .macOS),
        ]

        // When
        let nodes = try libraries.map { try SDKNode(name: $0.name, platform: $0.platform, status: .required, source: .developer) }

        // Then
        XCTAssertEqual(nodes.map(\.path), [
            "/Platforms/iPhoneOS.platform/Developer/Library/Frameworks/XCTest.framework",
            "/Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework",
        ])
    }

    func test_xctest_sdk_framework_unsupported_platforms_path() throws {
        XCTAssertThrowsSpecific(try SDKNode(name: "XCTest.framework", platform: .tvOS, status: .required, source: .developer),
                                SDKNode.Error.unsupported(sdk: "XCTest.framework"))
        XCTAssertThrowsSpecific(try SDKNode(name: "XCTest.framework", platform: .watchOS, status: .required, source: .developer),
                                SDKNode.Error.unsupported(sdk: "XCTest.framework"))
    }

    func test_sdk_library_paths() throws {
        // Given
        let libraries: [(name: String, platform: Platform)] = [
            ("libFoo.tbd", .iOS),
            ("libBar.tbd", .macOS),
            ("libFooBar.tbd", .tvOS),
        ]

        // When
        let nodes = try libraries.map { try SDKNode(name: $0.name, platform: $0.platform, status: .required, source: .developer) }

        // Then
        XCTAssertEqual(nodes.map(\.path), [
            "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/usr/lib/libFoo.tbd",
            "/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib/libBar.tbd",
            "/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/lib/libFooBar.tbd",
        ])
    }

    func test_name_removesTheExtension() throws {
        // Given
        let subject = try SDKNode(name: "CoreData.framework",
                                  platform: .iOS,
                                  status: .required,
                                  source: .developer)

        // When
        let got = subject.name

        // Then
        XCTAssertEqual(got, "CoreData")
    }
}
