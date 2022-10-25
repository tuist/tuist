import Foundation
import ProjectDescription
import TuistGraph

extension TuistGraph.Platform {
    /// Maps a ProjectDescription.Platform instance into a TuistGraph.Platform instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of platform model.
    static func from(manifest: ProjectDescription.Platform) -> TuistGraph.Platform {
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

    /// Maps a ProjectDescription.Target instance into a [TuistGraph.Platform] instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of target model.
    static func from(manifest: ProjectDescription.Target) -> [TuistGraph.Platform] {
        manifest.deploymentTargets.map { TuistGraph.Platform.from(deploymentTarget: $0) }
    }

    /// Maps a DeploymentTarget. instance into a TuistGraph.Platform instance.
    /// - Parameters:
    ///   - deploymentTarget: Deployment target model.
    static func from(deploymentTarget: ProjectDescription.DeploymentTarget) -> TuistGraph.Platform {
        switch deploymentTarget {
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
}
