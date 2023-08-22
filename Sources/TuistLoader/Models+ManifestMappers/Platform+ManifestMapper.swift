import Foundation
import ProjectDescription
import TuistGraph

extension TuistGraph.Platform {
    /// Maps a ProjectDescription.Platform instance into a TuistGraph.Platform instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of platform model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Platform) throws -> TuistGraph.Platform {
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
