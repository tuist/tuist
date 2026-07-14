import FileSystem
import Foundation
import Path

/// Normalizes a cached resource `.bundle` so it can be embedded into a build for any destination.
///
/// Cache warm builds resource `.bundle` targets for the simulator SDK only, so the bundle's
/// `Info.plist` ends up with `CFBundleSupportedPlatforms = [iPhoneSimulator]`. When that cached
/// bundle is embedded into a device archive, App Store Connect rejects the upload with error 90542
/// ("Invalid CFBundleSupportedPlatforms value").
///
/// A resource bundle carries no executable code, so the key is meaningless for it and Apple's
/// guidance is to remove it (https://developer.apple.com/library/archive/qa/qa1964/_index.html).
/// Stripping it makes the cached bundle valid for both device and simulator consumers regardless of
/// which SDK it was built against.
public struct CachedBundlePlatformNormalizer {
    private static let supportedPlatformsKey = "CFBundleSupportedPlatforms"

    private let fileSystem: FileSysteming

    public init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    /// Removes the `CFBundleSupportedPlatforms` key from every `Info.plist` inside the bundle at
    /// `bundlePath` (the bundle's own plist and any nested bundles).
    public func normalize(bundleAt bundlePath: AbsolutePath) async throws {
        let infoPlists = try await fileSystem.glob(
            directory: bundlePath,
            include: ["Info.plist", "**/Info.plist"]
        ).collect()

        for infoPlist in Set(infoPlists) {
            try await removeSupportedPlatforms(from: infoPlist)
        }
    }

    private func removeSupportedPlatforms(from infoPlistPath: AbsolutePath) async throws {
        let data = try await fileSystem.readFile(at: infoPlistPath)

        var format = PropertyListSerialization.PropertyListFormat.binary
        guard var dictionary = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: &format
        ) as? [String: Any],
            dictionary[Self.supportedPlatformsKey] != nil
        else { return }

        dictionary.removeValue(forKey: Self.supportedPlatformsKey)

        let normalizedData = try PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: format,
            options: 0
        )
        try normalizedData.write(to: infoPlistPath.url)
    }
}
