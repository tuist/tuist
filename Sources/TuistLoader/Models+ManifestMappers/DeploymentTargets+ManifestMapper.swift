import Foundation
import ProjectDescription
import TuistCore
import TuistGraph

extension TuistGraph.DeploymentTargets {
    /// Maps a ProjectDescription.DeploymentTargets instance into a TuistGraph.DeploymentTarget instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of deployment target model.
    static func from(manifest: ProjectDescription.DeploymentTargets) -> TuistGraph.DeploymentTargets {
        TuistGraph.DeploymentTargets(
            iOS: manifest.iOS,
            macOS: manifest.macOS,
            watchOS: manifest.watchOS,
            tvOS: manifest.tvOS,
            visionOS: manifest.visionOS
        )
    }

    /// Maps a ProjectDescription.DeploymentTarget instance into a TuistGraph.DeploymentTarget instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of deployment target model.
    static func from(manifest: ProjectDescription.DeploymentTarget?) -> TuistGraph.DeploymentTargets {
        if let manifest {
            switch manifest {
            case let .iOS(version, _, _):
                return .iOS(version)
            case let .macOS(version):
                return .macOS(version)
            case let .watchOS(version):
                return .watchOS(version)
            case let .tvOS(version):
                return .tvOS(version)
            case let .visionOS(version):
                return .visionOS(version)
            }
        } else {
            return .empty()
        }
    }
}
