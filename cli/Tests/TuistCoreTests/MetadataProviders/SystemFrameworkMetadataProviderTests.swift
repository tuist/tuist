import Testing
import XcodeGraph
@testable import TuistCore
@testable import TuistTesting

struct SystemFrameworkMetadataProviderTests {
    let subject: SystemFrameworkMetadataProvider

    init() {
        subject = SystemFrameworkMetadataProvider()
    }

    @Test func loadMetadata_framework() throws {
        // Given
        let sdkName = "UIKit.framework"

        // When
        let metadata = try subject.loadMetadata(sdkName: sdkName, status: .required, platform: .iOS, source: .system)

        // Then
        #expect(metadata == SystemFrameworkMetadata(
            name: sdkName,
            path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/UIKit.framework",
            status: .required,
            source: .system
        ))
    }

    @Test func loadMetadata_library() throws {
        // Given
        let sdkName = "libc++.tbd"

        // When
        let metadata = try subject.loadMetadata(sdkName: sdkName, status: .required, platform: .iOS, source: .system)

        // Then
        #expect(metadata == SystemFrameworkMetadata(
            name: sdkName,
            path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/usr/lib/libc++.tbd",
            status: .required,
            source: .system
        ))
    }

    @Test func loadMetadata_swiftLibrary() throws {
        // Given
        let sdkName = "libswiftObservation.tbd"

        // When
        let metadata = try subject.loadMetadata(sdkName: sdkName, status: .required, platform: .iOS, source: .system)

        // Then
        #expect(metadata == SystemFrameworkMetadata(
            name: sdkName,
            path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/usr/lib/swift/libswiftObservation.tbd",
            status: .required,
            source: .system
        ))
    }

    @Test func loadMetadata_unsupportedType() throws {
        // Given
        let sdkName = "UIKit.xcframework"

        // When / Then
        #expect(throws: SystemFrameworkMetadataProviderError.unsupportedSDK(name: "UIKit.xcframework")) {
            try subject.loadMetadata(sdkName: sdkName, status: .required, platform: .iOS, source: .system)
        }
    }

    @Test func loadMetadata_developerSource_supportedPlatform() throws {
        // Given
        let sdkName = "XCTest.framework"
        let source = SDKSource.developer
        let platform = Platform.iOS

        // When
        let metadata = try subject.loadMetadata(sdkName: sdkName, status: .required, platform: platform, source: source)

        // Then
        #expect(metadata == SystemFrameworkMetadata(
            name: sdkName,
            path: "/Platforms/iPhoneOS.platform/Developer/Library/Frameworks/XCTest.framework",
            status: .required,
            source: .developer
        ))
    }
}
