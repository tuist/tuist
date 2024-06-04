import Foundation
import ProjectDescription
import XcodeProjectGenerator

extension XcodeProjectGenerator.Platform {
    /// Maps a ProjectDescription.Platform instance into a XcodeProjectGenerator.Platform instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of platform model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Platform) throws -> XcodeProjectGenerator.Platform {
        switch manifest {
        case .macOS:
            return .macOS
        case .iOS:
            return .iOS
        case .tvOS:
            return .tvOS
        case .watchOS:
            return .watchOS
        case .visionOS:
            return .visionOS
        }
    }
}

extension XcodeProjectGenerator.PackagePlatform {
    /// Maps a ProjectDescription.Platform instance into a XcodeProjectGenerator.Platform instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of platform model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.PackagePlatform) throws -> XcodeProjectGenerator.PackagePlatform {
        switch manifest {
        case .macOS:
            return .macOS
        case .iOS:
            return .iOS
        case .macCatalyst:
            return .macCatalyst
        case .tvOS:
            return .tvOS
        case .watchOS:
            return .watchOS
        case .visionOS:
            return .visionOS
        }
    }
}
