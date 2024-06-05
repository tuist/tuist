import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.Arguments {
    /// Maps a ProjectDescription.Arguments instance into a XcodeGraph.Arguments instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of arguments model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Arguments) -> XcodeGraph.Arguments {
        Arguments(
            environmentVariables: manifest.environmentVariables.mapValues(EnvironmentVariable.from),
            launchArguments: manifest.launchArguments.map(LaunchArgument.from)
        )
    }
}
