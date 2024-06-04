import Foundation
import ProjectDescription
import TuistCore
import XcodeProjectGenerator

extension XcodeProjectGenerator.EnvironmentVariable {
    /// Maps a ProjectDescription.EnvironmentVariable instance into a XcodeProjectGenerator.EnvironmentVariable instance.
    /// - Parameters:
    ///   - manifest: Manifest representation of environment variable model.
    static func from(manifest: ProjectDescription.EnvironmentVariable) -> XcodeProjectGenerator.EnvironmentVariable {
        EnvironmentVariable(value: manifest.value, isEnabled: manifest.isEnabled)
    }
}
