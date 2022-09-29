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
        }
    }
    
    static func from(manifest: ProjectDescription.Target) throws -> [TuistGraph.Platform] {
        var platforms = [TuistGraph.Platform]()
        
        for deploymentTarget in manifest.deploymentTargets {
            switch deploymentTarget {
            case .macOS:
                platforms.append(.macOS)
            case .iOS:
                platforms.append(.iOS)
            case .tvOS:
                platforms.append(.tvOS)
            case .watchOS:
                platforms.append(.watchOS)
            }
        }
        
        return platforms
    }
}
