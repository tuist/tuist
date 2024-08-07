import FileSystem
import Foundation
import MockableTest
import Path
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistAutomation

final class AppBundleLoaderTests: TuistUnitTestCase {
    private var subject: AppBundleLoader!

    override func setUp() {
        super.setUp()

        subject = AppBundleLoader(fileSystem: FileSystem())
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func test_load_app_bundle() async throws {
        // Given
        let appBundlePath = fixturePath(path: try RelativePath(validating: "App.app"))

        // When
        let appBundle = try await subject.load(appBundlePath)

        // Then
        XCTAssertEqual(
            appBundle,
            AppBundle(
                path: appBundlePath,
                infoPlist: AppBundle.InfoPlist(
                    version: Version("1.0"),
                    name: "App",
                    bundleId: "io.tuist.App",
                    minimumOSVersion: Version("17.4"),
                    supportedPlatforms: [.simulator(.iOS)]
                )
            )
        )
    }

    func test_load_app_bundle_when_info_plist_is_missing_does_not_exist() async throws {
        // Given
        let appBundlePath = try temporaryPath()

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.load(appBundlePath),
            AppBundleLoaderError.missingInfoPlist(appBundlePath.appending(component: "Info.plist"))
        )
    }

    func test_load_app_bundle_when_decoding_info_plist_failed() async throws {
        // Given
        let appBundlePath = try temporaryPath()
        let infoPlistPath = appBundlePath.appending(component: "Info.plist")
        try fileHandler.write("{}", path: infoPlistPath, atomically: true)

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.load(appBundlePath),
            AppBundleLoaderError.failedDecodingInfoPlist(infoPlistPath, "The data couldn’t be read because it is missing.")
        )
    }
}
