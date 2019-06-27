import Basic
import Foundation
import XCTest

import TuistCoreTesting
@testable import TuistGenerator

final class SDKNodeTests: XCTestCase {
    func test_sdk_supportedTypes() throws {
        // Given
        let libraries = [
            "Foo.framework",
            "libBar.tbd",
        ]

        // When / Then
        XCTAssertNoThrow(try libraries.map { try SDKNode(name: $0, platform: .macOS, status: .required) })
    }

    func test_sdk_usupportedTypes() throws {
        XCTAssertThrowsError(try SDKNode(name: "FooBar", platform: .tvOS, status: .required)) { error in
            XCTAssertEqual(error as? SDKNode.Error, .unsupported(sdk: "FooBar"))
        }
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
        let nodes = try libraries.map { try SDKNode(name: $0.name, platform: $0.platform, status: .required) }

        // Then
        XCTAssertEqual(nodes.map(\.path), [
            "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/Foo.framework",
            "/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/Bar.framework",
            "/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/System/Library/Frameworks/FooBar.framework",
        ])
    }

    func test_sdk_library_paths() throws {
        // Given
        let libraries: [(name: String, platform: Platform)] = [
            ("libFoo.tbd", .iOS),
            ("libBar.tbd", .macOS),
            ("libFooBar.tbd", .tvOS),
        ]

        // When
        let nodes = try libraries.map { try SDKNode(name: $0.name, platform: $0.platform, status: .required) }

        // Then
        XCTAssertEqual(nodes.map(\.path), [
            "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/usr/lib/libFoo.tbd",
            "/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/lib/libBar.tbd",
            "/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/lib/libFooBar.tbd",
        ])
    }
}
