import Foundation
import ProjectDescription
import TuistCore
import TuistGraph

extension TuistGraph.LaunchArgument {
    /// Maps a ProjectDescription.LaunchArgument instance into a TuistGraph.LaunchArgument instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of launch argument model.
    static func from(manifest: ProjectDescription.LaunchArgument) -> TuistGraph.LaunchArgument {
        LaunchArgument(name: manifest.name, isEnabled: manifest.isEnabled)
    }
}
