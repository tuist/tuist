import Foundation
import ProjectDescription
import TuistCore
import XcodeProjectGenerator

extension XcodeProjectGenerator.DeploymentTargets {
    /// Maps a ProjectDescription.DeploymentTargets instance into a XcodeProjectGenerator.DeploymentTarget instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of deployment target model.
    static func from(manifest: ProjectDescription.DeploymentTargets) -> XcodeProjectGenerator.DeploymentTargets {
        XcodeProjectGenerator.DeploymentTargets(
            iOS: manifest.iOS,
            macOS: manifest.macOS,
            watchOS: manifest.watchOS,
            tvOS: manifest.tvOS,
            visionOS: manifest.visionOS
        )
    }
}
