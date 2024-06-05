import Foundation
import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.EnvironmentVariable {
    /// Maps a ProjectDescription.EnvironmentVariable instance into a XcodeGraph.EnvironmentVariable instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of environment variable model.
    static func from(manifest: ProjectDescription.EnvironmentVariable) -> XcodeGraph.EnvironmentVariable {
        EnvironmentVariable(value: manifest.value, isEnabled: manifest.isEnabled)
    }
}
