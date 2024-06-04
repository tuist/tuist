import Foundation
import ProjectDescription
import TuistCore
import XcodeProjectGenerator

extension XcodeProjectGenerator.LaunchArgument {
    /// Maps a ProjectDescription.LaunchArgument instance into a XcodeProjectGenerator.LaunchArgument instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of launch argument model.
    static func from(manifest: ProjectDescription.LaunchArgument) -> XcodeProjectGenerator.LaunchArgument {
        LaunchArgument(name: manifest.name, isEnabled: manifest.isEnabled)
    }
}
