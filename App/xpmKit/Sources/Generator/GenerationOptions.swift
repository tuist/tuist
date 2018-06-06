import Basic
import Foundation

/// Generation options.
class GenerationOptions {
    /// Build configuration to be generated (Debug or Release)
    let buildConfiguration: BuildConfiguration

    /// Initializes the options with its attributes.
    ///
    /// - Parameters:
    ///   - buildConfiguration: build configuration.
    init(buildConfiguration: BuildConfiguration = .debug) {
        self.buildConfiguration = buildConfiguration
    }
}
