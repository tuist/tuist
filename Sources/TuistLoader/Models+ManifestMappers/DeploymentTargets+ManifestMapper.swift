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
}
