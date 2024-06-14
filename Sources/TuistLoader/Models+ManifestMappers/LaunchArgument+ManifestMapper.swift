import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.LaunchArgument {
    /// Maps a ProjectDescription.LaunchArgument instance into a XcodeGraph.LaunchArgument instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of launch argument model.
    static func from(manifest: ProjectDescription.LaunchArgument) -> XcodeGraph.LaunchArgument {
        LaunchArgument(name: manifest.name, isEnabled: manifest.isEnabled)
    }
}
