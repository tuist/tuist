import FileSystem
import Foundation
import Path
import Testing

@testable import Rosalind

@Suite struct AppBundleLoaderTests {
    private let fileSystem = FileSystem()
    private let subject = AppBundleLoader()

    @Test func loadFlatAppBundle() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let appBundlePath = temporaryDirectory.appending(component: "App.app")
            try await fileSystem.makeDirectory(at: appBundlePath)
            try await fileSystem.writeText("""
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>CFBundleIdentifier</key>
                <string>io.tuist.App</string>
                <key>CFBundleName</key>
                <string>App</string>
                <key>CFBundleShortVersionString</key>
                <string>1.0</string>
                <key>CFBundleVersion</key>
                <string>1</string>
                <key>CFBundleSupportedPlatforms</key>
                <array>
                    <string>iPhoneOS</string>
                </array>
                <key>MinimumOSVersion</key>
                <string>17.0</string>
            </dict>
            </plist>
            """, at: appBundlePath.appending(component: "Info.plist"))

            // When
            let appBundle = try await subject.load(appBundlePath)

            // Then
            #expect(appBundle.infoPlist.bundleId == "io.tuist.App")
            #expect(appBundle.infoPlist.name == "App")
            #expect(appBundle.infoPlist.version == "1.0")
            #expect(appBundle.infoPlist.minimumOSVersion == "17.0")
            #expect(appBundle.infoPlist.supportedPlatforms == ["iPhoneOS"])
        }
    }

    @Test func loadMacOSAppBundle() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let appBundlePath = temporaryDirectory.appending(component: "App.app")
            let contentsPath = appBundlePath.appending(component: "Contents")
            try await fileSystem.makeDirectory(at: contentsPath)
            try await fileSystem.writeText("""
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>CFBundleIdentifier</key>
                <string>io.tuist.MacApp</string>
                <key>CFBundleName</key>
                <string>MacApp</string>
                <key>CFBundleShortVersionString</key>
                <string>2.0</string>
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
            """, at: contentsPath.appending(component: "Info.plist"))

            // When
            let appBundle = try await subject.load(appBundlePath)

            // Then
            #expect(appBundle.infoPlist.bundleId == "io.tuist.MacApp")
            #expect(appBundle.infoPlist.name == "MacApp")
            #expect(appBundle.infoPlist.version == "2.0")
            #expect(appBundle.infoPlist.minimumOSVersion == "14.0")
            #expect(appBundle.infoPlist.supportedPlatforms == ["MacOSX"])
        }
    }

    @Test func loadMissingInfoPlist() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let appBundlePath = temporaryDirectory.appending(component: "App.app")
            try await fileSystem.makeDirectory(at: appBundlePath)

            // When / Then
            await #expect(throws: AppBundleLoaderError.self) {
                try await subject.load(appBundlePath)
            }
        }
    }
}
