import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistSupport
import TuistTesting
import XcodeGraph

@testable import TuistAutomation

struct AppBundleLoaderTests {
    private let subject: AppBundleLoader
    private let fileSystem = FileSystem()
    private let fileHandler = FileHandler.shared
    init() {
        subject = AppBundleLoader(
            fileSystem: FileSystem()
        )
    }

    @Test(.inTemporaryDirectory)
    func load_ipa_when_it_does_not_contain_any_app_bundle() async throws {
        // Given
        let ipaPath = try #require(FileSystem.temporaryTestDirectory).appending(components: "App.ipa")
        let payloadPath = try #require(FileSystem.temporaryTestDirectory).appending(components: "Payload")
        try await fileSystem.touch(ipaPath)
        let fileArchiverFactory = MockFileArchivingFactorying()
        let fileUnarchiver = MockFileUnarchiving()
        given(fileArchiverFactory)
            .makeFileUnarchiver(for: .any)
            .willReturn(fileUnarchiver)
        given(fileUnarchiver)
            .unzip()
            .willReturn(payloadPath)
        let subject = AppBundleLoader(
            fileSystem: fileSystem,
            fileArchiverFactory: fileArchiverFactory
        )

        // When / Then
        await #expect(throws: AppBundleLoaderError.appBundleInIPANotFound(ipaPath)) { try await subject.load(
            ipa: ipaPath
        ) }
    }

    @Test
    func load_ipa() async throws {
        // Given
        let ipaPath = SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "App.ipa"))

        // When
        let appBundle = try await subject.load(ipa: ipaPath)

        // Then
        #expect(appBundle == AppBundle(
            path: ipaPath,
            infoPlist: AppBundle.InfoPlist(
                version: "0.9.0",
                buildVersion: "0.9.0",
                name: "Tuist",
                executableName: "Tuist",
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
        ))
    }

    @Test
    func load_app_bundle() async throws {
        // Given
        let appBundlePath = SwiftTestingHelper.fixturePath(path: try RelativePath(validating: "App.app"))

        // When
        let appBundle = try await subject.load(appBundlePath)

        // Then
        #expect(appBundle == AppBundle(
            path: appBundlePath,
            infoPlist: AppBundle.InfoPlist(
                version: "1.0",
                buildVersion: "1",
                name: "App",
                executableName: "App",
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
        ))
    }

    @Test
    func load_iphoneos_app_bundle() async throws {
        // Given
        let appBundlePath = SwiftTestingHelper.fixturePath(
            path: try RelativePath(validating: "ios_app_with_frameworks_iphoneos-App.app")
        )

        // When
        let appBundle = try await subject.load(appBundlePath)

        // Then
        #expect(appBundle == AppBundle(
            path: appBundlePath,
            infoPlist: AppBundle.InfoPlist(
                version: "1.0",
                buildVersion: "1",
                name: "App",
                executableName: "App",
                bundleId: "io.tuist.App",
                minimumOSVersion: Version("17.0"),
                supportedPlatforms: [.device(.iOS)],
                bundleIcons: nil
            )
        ))
    }

    @Test(.inTemporaryDirectory)
    func load_appletv_info_plist() async throws {
        // Given
        let appBundlePath = try #require(FileSystem.temporaryTestDirectory)
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
        #expect(appBundle == AppBundle(
            path: appBundlePath,
            infoPlist: AppBundle.InfoPlist(
                version: "1.0",
                buildVersion: "1",
                name: "App",
                executableName: nil,
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
        ))
    }

    @Test(.inTemporaryDirectory)
    func load_info_plist_with_primary_icon_and_and_no_bundle_icon_name() async throws {
        // Given
        let appBundlePath = try #require(FileSystem.temporaryTestDirectory)
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
        #expect(appBundle == AppBundle(
            path: appBundlePath,
            infoPlist: AppBundle.InfoPlist(
                version: "1.0",
                buildVersion: "1",
                name: "App",
                executableName: nil,
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
        ))
    }

    @Test(.inTemporaryDirectory)
    func load_macos_app_bundle() async throws {
        // Given
        let appBundlePath = try #require(FileSystem.temporaryTestDirectory).appending(component: "App.app")
        let contentsPath = appBundlePath.appending(component: "Contents")
        try await fileSystem.makeDirectory(at: contentsPath)
        let infoPlistPath = contentsPath.appending(component: "Info.plist")
        try fileHandler.write("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>io.tuist.MacApp</string>
            <key>CFBundleName</key>
            <string>MacApp</string>
            <key>CFBundleExecutable</key>
            <string>MacApp</string>
            <key>CFBundleShortVersionString</key>
            <string>1.0</string>
            <key>CFBundleVersion</key>
            <string>1</string>
            <key>CFBundleSupportedPlatforms</key>
            <array>
                <string>MacOSX</string>
            </array>
            <key>LSMinimumSystemVersion</key>
            <string>14.0</string>
        </dict>
        </plist>
        """, path: infoPlistPath, atomically: true)

        // When
        let appBundle = try await subject.load(appBundlePath)

        // Then
        #expect(appBundle == AppBundle(
            path: appBundlePath,
            infoPlist: AppBundle.InfoPlist(
                version: "1.0",
                buildVersion: "1",
                name: "MacApp",
                executableName: "MacApp",
                bundleId: "io.tuist.MacApp",
                minimumOSVersion: Version("14.0"),
                supportedPlatforms: [.device(.macOS)],
                bundleIcons: nil
            )
        ))
    }

    @Test(.inTemporaryDirectory)
    func load_app_bundle_when_info_plist_is_missing_does_not_exist() async throws {
        // Given
        let appBundlePath = try #require(FileSystem.temporaryTestDirectory)

        // When / Then
        await #expect(throws: AppBundleLoaderError.missingInfoPlist(appBundlePath.appending(component: "Info.plist"))) {
            try await subject.load(appBundlePath)
        }
    }

    @Test(.inTemporaryDirectory)
    func load_app_bundle_when_decoding_info_plist_failed() async throws {
        // Given
        let appBundlePath = try #require(FileSystem.temporaryTestDirectory)
        let infoPlistPath = appBundlePath.appending(component: "Info.plist")
        try fileHandler.write("{}", path: infoPlistPath, atomically: true)

        // When / Then
        await #expect(throws: AppBundleLoaderError.failedDecodingInfoPlist(
            infoPlistPath,
            "The data couldn’t be read because it is missing."
        )) { try await subject.load(appBundlePath) }
    }
}
