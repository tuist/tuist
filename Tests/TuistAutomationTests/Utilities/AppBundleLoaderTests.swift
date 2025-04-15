import FileSystem
import Foundation
import Mockable
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
        XCTAssertBetterEqual(
            appBundle,
            AppBundle(
                path: appBundlePath,
                infoPlist: AppBundle.InfoPlist(
                    version: "1.0",
                    name: "App",
                    bundleId: "io.tuist.MainApp",
                    minimumOSVersion: Version("17.0"),
                    supportedPlatforms: [.simulator(.iOS)],
                    bundleIcons: AppBundle.InfoPlist.BundleIcons(
                        primaryIcon: AppBundle.InfoPlist.PrimaryBundleIcon.dictionary(
                            name: "AppIcon",
                            iconFiles: ["AppIcon60x60"]
                        )
                    )
                )
            )
        )
    }

    func test_load_iphoneos_app_bundle() async throws {
        // Given
        let appBundlePath = fixturePath(
            path: try RelativePath(validating: "ios_app_with_frameworks_iphoneos-App.app")
        )

        // When
        let appBundle = try await subject.load(appBundlePath)

        // Then
        XCTAssertBetterEqual(
            appBundle,
            AppBundle(
                path: appBundlePath,
                infoPlist: AppBundle.InfoPlist(
                    version: "1.0",
                    name: "App",
                    bundleId: "io.tuist.App",
                    minimumOSVersion: Version("17.0"),
                    supportedPlatforms: [.device(.iOS)],
                    bundleIcons: nil
                )
            )
        )
    }

    // TODO: Ask for signed tvOS app
    func test_load_appletv_app_bundle() async throws {
        // Given
        let appBundlePath = fixturePath(path: try RelativePath(validating: "tvOS-App.app"))

        // When
        let appBundle = try await subject.load(appBundlePath)

        // Then
        XCTAssertBetterEqual(
            appBundle,
            AppBundle(
                path: appBundlePath,
                infoPlist: AppBundle.InfoPlist(
                    version: "1.0",
                    name: "App",
                    bundleId: "io.tuist.App",
                    minimumOSVersion: Version("18.2"),
                    supportedPlatforms: [.device(.tvOS)],
                    bundleIcons: AppBundle.InfoPlist.BundleIcons(
                        primaryIcon: AppBundle.InfoPlist.PrimaryBundleIcon.string("App Icon")
                    )
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
