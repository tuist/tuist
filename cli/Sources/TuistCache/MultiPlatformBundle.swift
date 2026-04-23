import FileSystem
import Foundation
import Path
import XcodeGraph

public enum MultiPlatformBundle {
    public static let bundleExtension = "xcbundle"
    public static let manifestFileName = "Info.plist"

    public struct Slice: Hashable, Codable {
        public let libraryIdentifier: String
        public let supportedPlatforms: [String]
        public let bundleName: String

        public init(libraryIdentifier: String, supportedPlatforms: [String], bundleName: String) {
            self.libraryIdentifier = libraryIdentifier
            self.supportedPlatforms = supportedPlatforms
            self.bundleName = bundleName
        }

        public var platformFilters: PlatformFilters {
            Set(supportedPlatforms.compactMap(PlatformFilter.init(xcodeprojValue:)))
        }

        public func bundlePath(inside wrapper: AbsolutePath) throws -> AbsolutePath {
            try wrapper.appending(
                RelativePath(validating: "\(libraryIdentifier)/\(bundleName)")
            )
        }

        private enum CodingKeys: String, CodingKey {
            case libraryIdentifier = "LibraryIdentifier"
            case supportedPlatforms = "SupportedPlatforms"
            case bundleName = "BundleName"
        }
    }

    public struct Manifest: Codable {
        public let version: Int
        public let slices: [Slice]

        public init(slices: [Slice]) {
            version = 1
            self.slices = slices
        }

        private enum CodingKeys: String, CodingKey {
            case version = "TuistMultiPlatformBundleVersion"
            case slices = "Slices"
        }
    }

    public static func libraryIdentifier(for platform: Platform) -> String {
        switch platform {
        case .iOS: return "ios"
        case .macOS: return "macos"
        case .tvOS: return "tvos"
        case .watchOS: return "watchos"
        case .visionOS: return "visionos"
        }
    }

    public static func supportedPlatformFilters(for platform: Platform) -> [PlatformFilter] {
        switch platform {
        case .iOS: return [.ios, .catalyst]
        case .macOS: return [.macos]
        case .tvOS: return [.tvos]
        case .watchOS: return [.watchos]
        case .visionOS: return [.visionos]
        }
    }

    public static func readManifest(
        at wrapperPath: AbsolutePath,
        fileSystem: FileSysteming
    ) async throws -> Manifest {
        let plistPath = wrapperPath.appending(component: manifestFileName)
        return try await fileSystem.readPlistFile(at: plistPath)
    }

    public static func writeManifest(
        _ manifest: Manifest,
        to wrapperPath: AbsolutePath,
        fileSystem: FileSysteming
    ) async throws {
        try await fileSystem.writeAsPlist(manifest, at: wrapperPath.appending(component: manifestFileName))
    }
}

extension PlatformFilter {
    public init?(xcodeprojValue: String) {
        switch xcodeprojValue {
        case "ios": self = .ios
        case "macos": self = .macos
        case "tvos": self = .tvos
        case "maccatalyst": self = .catalyst
        case "driverkit": self = .driverkit
        case "watchos": self = .watchos
        case "xros": self = .visionos
        default: return nil
        }
    }
}
