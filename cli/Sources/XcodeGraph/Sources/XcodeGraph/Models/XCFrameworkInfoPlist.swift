import Foundation
import Path

/// It represents th Info.plist contained in an .xcframework bundle.
public struct XCFrameworkInfoPlist: Codable, Hashable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case libraries = "AvailableLibraries"
    }

    /// It represents a library inside an .xcframework
    public struct Library: Codable, Hashable, Equatable, Sendable {
        public enum Platform: String, CaseIterable, Codable, Sendable {
            case iOS = "ios"
            case macOS = "macos"
            case tvOS = "tvos"
            case watchOS = "watchos"
            case visionOS = "xros" // Note: for visionOS, the rawValue is `xros`
        }

        public enum PlatformVariant: String, Codable, Hashable, Sendable {
            case simulator
            case maccatalyst
        }

        private enum CodingKeys: String, CodingKey {
            case identifier = "LibraryIdentifier"
            case path = "LibraryPath"
            case platform = "SupportedPlatform"
            case platformVariant = "SupportedPlatformVariant"
            case architectures = "SupportedArchitectures"
            case mergeable = "MergeableMetadata"
        }

        /// Binary name used to import the library
        public var binaryName: String {
            path.basenameWithoutExt
        }

        /// Library identifier.
        public let identifier: String

        /// Path to the library.
        public let path: RelativePath

        /// Declares if the library is mergeable or not
        public let mergeable: Bool

        public let platform: Self.Platform

        /// Platform variant (e.g. simulator, maccatalyst). Nil for device slices.
        public let platformVariant: PlatformVariant?

        /// Architectures the binary is built for.
        public let architectures: [BinaryArchitecture]

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(identifier, forKey: .identifier)
            try container.encode(path, forKey: .path)
            try container.encode(mergeable, forKey: .mergeable)
            try container.encode(architectures, forKey: .architectures)
            try container.encode(platform, forKey: .platform)
            try container.encodeIfPresent(platformVariant, forKey: .platformVariant)
        }

        public init(
            identifier: String,
            path: RelativePath,
            mergeable: Bool,
            platform: Platform,
            platformVariant: PlatformVariant? = nil,
            architectures: [BinaryArchitecture]
        ) {
            self.identifier = identifier
            self.path = path
            self.mergeable = mergeable
            self.platform = platform
            self.platformVariant = platformVariant
            self.architectures = architectures
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            identifier = try container.decode(String.self, forKey: .identifier)
            path = try container.decode(RelativePath.self, forKey: .path)
            platform = try container.decode(Platform.self, forKey: .platform)
            platformVariant = try container.decodeIfPresent(PlatformVariant.self, forKey: .platformVariant)
            architectures = try container.decode([BinaryArchitecture].self, forKey: .architectures)
            mergeable = try container.decodeIfPresent(Bool.self, forKey: .mergeable) ?? false
        }

        #if DEBUG
            public static func test(
                identifier: String = "test",
                // swiftlint:disable:next force_try
                path: RelativePath = try! RelativePath(validating: "relative/to/library"),
                mergeable: Bool = false,
                platform: Platform = .iOS,
                platformVariant: PlatformVariant? = nil,
                architectures: [BinaryArchitecture] = [.i386]
            ) -> XCFrameworkInfoPlist.Library {
                XCFrameworkInfoPlist.Library(
                    identifier: identifier,
                    path: path,
                    mergeable: mergeable,
                    platform: platform,
                    platformVariant: platformVariant,
                    architectures: architectures
                )
            }
        #endif
    }

    /// List of libraries that are part of the .xcframework.
    public let libraries: [Library]

    public init(libraries: [Library]) {
        self.libraries = libraries
    }

    #if DEBUG
        public static func test(libraries: [XCFrameworkInfoPlist.Library] = [.test()]) -> XCFrameworkInfoPlist {
            XCFrameworkInfoPlist(libraries: libraries)
        }
    #endif
}
