import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.LaunchArgument {
    /// Maps a ProjectDescription.LaunchArgument instance into a TuistCore.LaunchArgument instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of launch argument model.
    static func from(manifest: ProjectDescription.LaunchArgument) -> TuistCore.LaunchArgument {
        LaunchArgument(name: manifest.name, isEnabled: manifest.isEnabled)
    }
}
