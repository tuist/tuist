import Foundation
import ProjectDescription
import XcodeGraph

extension XcodeGraph.Platform {
    /// Maps a ProjectDescription.Platform instance into a XcodeGraph.Platform instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of platform model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Platform) throws -> XcodeGraph.Platform {
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

extension XcodeGraph.PackagePlatform {
    /// Maps a ProjectDescription.Platform instance into a XcodeGraph.Platform instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of platform model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.PackagePlatform) throws -> XcodeGraph.PackagePlatform {
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
