import TSCBasic
import TuistGraph
import XCTest
@testable import TuistCore
@testable import TuistSupportTesting

final class SystemFrameworkMetadataProviderTests: XCTestCase {
    var subject: SystemFrameworkMetadataProvider!

    override func setUp() {
        super.setUp()
        subject = SystemFrameworkMetadataProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_loadMetadata_framework() throws {
        // Given
        let sdkName = "UIKit.framework"

        // When
        let metadata = try subject.loadMetadata(sdkName: sdkName, status: .required, platform: .iOS, source: .system)

        // Then
        XCTAssertEqual(metadata, SystemFrameworkMetadata(
            name: sdkName,
            path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/System/Library/Frameworks/UIKit.framework",
            status: .required,
            source: .system
        ))
    }

    func test_loadMetadata_library() throws {
        // Given
        let sdkName = "libc++.tbd"

        // When
        let metadata = try subject.loadMetadata(sdkName: sdkName, status: .required, platform: .iOS, source: .system)

        // Then
        XCTAssertEqual(metadata, SystemFrameworkMetadata(
            name: sdkName,
            path: "/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk/usr/lib/libc++.tbd",
            status: .required,
            source: .system
        ))
    }

    func test_loadMetadata_unsupportedType() throws {
        // Given
        let sdkName = "UIKit.xcframework"

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.loadMetadata(sdkName: sdkName, status: .required, platform: .iOS, source: .system),
            SystemFrameworkMetadataProviderError.unsupportedSDK(name: "UIKit.xcframework")
        )
    }

    func test_loadMetadata_developerSource_supportedPlatform() throws {
        // Given
        let sdkName = "XCTest.framework"
        let source = SDKSource.developer
        let platform = Platform.iOS

        // When
        let metadata = try subject.loadMetadata(sdkName: sdkName, status: .required, platform: platform, source: source)

        // Then
        XCTAssertEqual(metadata, SystemFrameworkMetadata(
            name: sdkName,
            path: "/Platforms/iPhoneOS.platform/Developer/Library/Frameworks/XCTest.framework",
            status: .required,
            source: .developer
        ))
    }
}
