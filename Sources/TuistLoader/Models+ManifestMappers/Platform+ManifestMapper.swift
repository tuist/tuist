import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.Platform {
    /// Maps a ProjectDescription.Platform instance into a TuistCore.Platform instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of platform model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Platform) throws -> TuistCore.Platform {
        switch manifest {
        case .macOS:
            return .macOS
        case .iOS:
            return .iOS
        case .tvOS:
            return .tvOS
        case .watchOS:
            return .watchOS
        case .notSpecified:
            return .notSpecified
        }
    }
}
