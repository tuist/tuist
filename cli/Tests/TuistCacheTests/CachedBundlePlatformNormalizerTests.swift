import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing

@testable import TuistCache

struct CachedBundlePlatformNormalizerTests {
    private let subject = CachedBundlePlatformNormalizer()

    @Test(.inTemporaryDirectory) func normalize_removes_supported_platforms_and_keeps_other_keys() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let bundlePath = temporaryDirectory.appending(component: "Sharing_Sharing.bundle")
        try FileManager.default.createDirectory(at: bundlePath.url, withIntermediateDirectories: true)
        try writePlist(
            [
                "CFBundleIdentifier": "com.example.Sharing",
                "CFBundleSupportedPlatforms": ["iPhoneSimulator"],
            ],
            at: bundlePath.appending(component: "Info.plist")
        )

        // When
        try await subject.normalize(bundleAt: bundlePath)

        // Then
        let plist = try readPlist(at: bundlePath.appending(component: "Info.plist"))
        #expect(plist["CFBundleSupportedPlatforms"] == nil)
        #expect(plist["CFBundleIdentifier"] as? String == "com.example.Sharing")
    }

    @Test(.inTemporaryDirectory) func normalize_removes_supported_platforms_from_nested_bundles() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let bundlePath = temporaryDirectory.appending(component: "Braze_Braze.bundle")
        let nestedBundlePath = bundlePath.appending(component: "Nested.bundle")
        try FileManager.default.createDirectory(at: nestedBundlePath.url, withIntermediateDirectories: true)
        try writePlist(
            ["CFBundleSupportedPlatforms": ["iPhoneSimulator"]],
            at: bundlePath.appending(component: "Info.plist")
        )
        try writePlist(
            ["CFBundleSupportedPlatforms": ["iPhoneSimulator"]],
            at: nestedBundlePath.appending(component: "Info.plist")
        )

        // When
        try await subject.normalize(bundleAt: bundlePath)

        // Then
        #expect(try readPlist(at: bundlePath.appending(component: "Info.plist"))["CFBundleSupportedPlatforms"] == nil)
        #expect(
            try readPlist(at: nestedBundlePath.appending(component: "Info.plist"))["CFBundleSupportedPlatforms"] == nil
        )
    }

    @Test(.inTemporaryDirectory) func normalize_is_noop_when_key_is_absent() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let bundlePath = temporaryDirectory.appending(component: "NoKey.bundle")
        try FileManager.default.createDirectory(at: bundlePath.url, withIntermediateDirectories: true)
        let infoPlistPath = bundlePath.appending(component: "Info.plist")
        try writePlist(["CFBundleIdentifier": "com.example.NoKey"], at: infoPlistPath)

        // When / Then
        try await subject.normalize(bundleAt: bundlePath)
        #expect(try readPlist(at: infoPlistPath)["CFBundleIdentifier"] as? String == "com.example.NoKey")
    }

    private func writePlist(_ dictionary: [String: Any], at path: AbsolutePath) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: dictionary, format: .binary, options: 0)
        try data.write(to: path.url)
    }

    private func readPlist(at path: AbsolutePath) throws -> [String: Any] {
        let data = try Data(contentsOf: path.url)
        return try #require(PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any])
    }
}
