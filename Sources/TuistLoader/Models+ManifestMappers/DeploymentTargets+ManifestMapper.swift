import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.DeploymentTargets {
    /// Maps a ProjectDescription.DeploymentTargets instance into a XcodeGraph.DeploymentTarget instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of deployment target model.
    static func from(manifest: ProjectDescription.DeploymentTargets) -> XcodeGraph.DeploymentTargets {
        XcodeGraph.DeploymentTargets(
            iOS: manifest.iOS,
            macOS: manifest.macOS,
            watchOS: manifest.watchOS,
            tvOS: manifest.tvOS,
            visionOS: manifest.visionOS
        )
    }
}
