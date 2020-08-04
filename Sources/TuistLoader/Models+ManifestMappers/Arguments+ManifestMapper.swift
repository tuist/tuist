import Foundation
import ProjectDescription
import TuistCore

extension TuistCore.Arguments {
    /// Maps a ProjectDescription.Arguments instance into a TuistCore.Arguments instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of arguments model.
    ///   - generatorPaths: Generator paths.
    static func from(manifest: ProjectDescription.Arguments) -> TuistCore.Arguments {
        Arguments(environment: manifest.environment, launchArguments: manifest.launchArguments)
    }
}
