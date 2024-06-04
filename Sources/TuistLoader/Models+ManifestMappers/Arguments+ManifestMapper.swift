import Foundation
import ProjectDescription
import TuistCore
import XcodeProjectGenerator

extension XcodeProjectGenerator.Arguments {
    /// Maps a ProjectDescription.Arguments instance into a XcodeProjectGenerator.Arguments instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of arguments model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Arguments) -> XcodeProjectGenerator.Arguments {
        Arguments(
            environmentVariables: manifest.environmentVariables.mapValues(EnvironmentVariable.from),
            launchArguments: manifest.launchArguments.map(LaunchArgument.from)
        )
    }
}
