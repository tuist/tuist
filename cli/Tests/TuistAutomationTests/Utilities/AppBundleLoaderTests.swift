import FileSystem
import Foundation
import Mockable
import Path
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest

@testable import TuistAutomation

final class AppBundleLoaderTests: TuistUnitTestCase {
    private var subject: AppBundleLoader!

    override func setUp() {
        super.setUp()

        subject = AppBundleLoader(
            fileSystem: FileSystem()
        )
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }

    func test_load_ipa_when_it_does_not_contain_any_app_bundle() async throws {
        // Given
        let ipaPath = try temporaryPath().appending(components: "App.ipa")
        let payloadPath = try temporaryPath().appending(components: "Payload")
        try await fileSystem.touch(ipaPath)
        let fileArchiverFactory = MockFileArchivingFactorying()
        let fileUnarchiver = MockFileUnarchiving()
        given(fileArchiverFactory)
            .makeFileUnarchiver(for: .any)
            .willReturn(fileUnarchiver)
        given(fileUnarchiver)
            .unzip()
            .willReturn(payloadPath)
        subject = AppBundleLoader(
            fileSystem: fileSystem,
            fileArchiverFactory: fileArchiverFactory
        )

        // When / Then
        await XCTAssertThrowsSpecific(
            try await subject.load(
                ipa: ipaPath
            ),
            AppBundleLoaderError.appBundleInIPANotFound(ipaPath)
        )
    }

    func test_load_ipa() async throws {
        // Given
        let ipaPath = fixturePath(path: try RelativePath(validating: "App.ipa"))

        // When
        let appBundle = try await subject.load(ipa: ipaPath)

        // Then
        XCTAssertBetterEqual(
            appBundle,
            AppBundle(
                path: ipaPath,
                infoPlist: AppBundle.InfoPlist(
                    version: "0.9.0",
                    buildVersion: "0.9.0",
                    name: "Tuist",
                    bundleId: "io.tuist.app",
                    minimumOSVersion: Version("18.4"),
                    supportedPlatforms: [.device(.iOS)],
                    bundleIcons: AppBundle.InfoPlist.BundleIcons(
                        primaryIcon: AppBundle.InfoPlist.PrimaryBundleIcon(
                            name: "AppIcon",
                            iconFiles: ["AppIcon60x60"]
                        )
                    )
                )
            )
        )
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
                    buildVersion: "1",
                    name: "App",
                    bundleId: "io.tuist.MainApp",
                    minimumOSVersion: Version("17.0"),
                    supportedPlatforms: [.simulator(.iOS)],
                    bundleIcons: AppBundle.InfoPlist.BundleIcons(
                        primaryIcon: AppBundle.InfoPlist.PrimaryBundleIcon(
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
                    buildVersion: "1",
                    name: "App",
                    bundleId: "io.tuist.App",
                    minimumOSVersion: Version("17.0"),
                    supportedPlatforms: [.device(.iOS)],
                    bundleIcons: nil
                )
            )
        )
    }

    func test_load_appletv_info_plist() async throws {
        // Given
        let appBundlePath = try temporaryPath()
        let infoPlistPath = appBundlePath.appending(component: "Info.plist")
        try fileHandler.write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIcons</key>
            <dict>
                <key>CFBundlePrimaryIcon</key>
                <string>App Icon</string>
            </dict>
            <key>CFBundleIdentifier</key>
            <string>io.tuist.TVApp</string>
            <key>CFBundleName</key>
            <string>App</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>CFBundleSupportedPlatforms</key>
            <array>
                <string>AppleTVOS</string>
            </array>
            <key>MinimumOSVersion</key>
            <string>18.2</string>
        </dict>
        </plist>
        """, path: infoPlistPath, atomically: true)

        // When
        let appBundle = try await subject.load(appBundlePath)

        // Then
        XCTAssertBetterEqual(
            appBundle,
            AppBundle(
                path: appBundlePath,
                infoPlist: AppBundle.InfoPlist(
                    version: "1.0",
                    buildVersion: "1",
                    name: "App",
                    bundleId: "io.tuist.TVApp",
                    minimumOSVersion: Version("18.2"),
                    supportedPlatforms: [.device(.tvOS)],
                    bundleIcons: AppBundle.InfoPlist.BundleIcons(
                        primaryIcon: AppBundle.InfoPlist.PrimaryBundleIcon(
                            name: "App Icon",
                            iconFiles: nil
                        )
                    )
                )
            )
        )
    }

    func test_load_info_plist_with_primary_icon_and_and_no_bundle_icon_name() async throws {
        // Given
        let appBundlePath = try temporaryPath()
        let infoPlistPath = appBundlePath.appending(component: "Info.plist")
        try fileHandler.write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIcons</key>
            <dict>
                <key>CFBundlePrimaryIcon</key>
                <dict>
                    <key>CFBundleIconFiles</key>
                    <array>
                        <string>AppIcon</string>
                    </array>
                    <key>UIPrerenderedIcon</key>
                    <false/>
                </dict>
            </dict>
            <key>CFBundleIdentifier</key>
            <string>io.tuist.TVApp</string>
            <key>CFBundleName</key>
            <string>App</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>CFBundleSupportedPlatforms</key>
            <array>
                <string>AppleTVOS</string>
            </array>
            <key>MinimumOSVersion</key>
            <string>18.2</string>
        </dict>
        </plist>
        """, path: infoPlistPath, atomically: true)

        // When
        let appBundle = try await subject.load(appBundlePath)

        // Then
        XCTAssertBetterEqual(
            appBundle,
            AppBundle(
                path: appBundlePath,
                infoPlist: AppBundle.InfoPlist(
                    version: "1.0",
                    buildVersion: "1",
                    name: "App",
                    bundleId: "io.tuist.TVApp",
                    minimumOSVersion: Version("18.2"),
                    supportedPlatforms: [.device(.tvOS)],
                    bundleIcons: AppBundle.InfoPlist.BundleIcons(
                        primaryIcon: AppBundle.InfoPlist.PrimaryBundleIcon(
                            name: "AppIcon",
                            iconFiles: ["AppIcon"]
                        )
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
