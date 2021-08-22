import Foundation
import ProjectDescription
import TuistCore
import TuistGraph

extension TuistGraph.EnvironmentVariable {
    /// Maps a ProjectDescription.EnvironmentVariable instance into a TuistGraph.EnvironmentVariable instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of the environment variable model.
    static func from(manifest: ProjectDescription.EnvironmentVariable) -> TuistGraph.EnvironmentVariable {
        EnvironmentVariable(key: manifest.key, value: manifest.value, isEnabled: manifest.isEnabled)
    }
}
