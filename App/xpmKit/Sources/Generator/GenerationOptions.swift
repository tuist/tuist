import Basic
import Foundation

/// Generation options.
class GenerationOptions {
    /// Build configuration to be generated (Debug or Release)
    let buildConfiguration: BuildConfiguration

    /// The folder where the project will be generated.
    let sourceRootPath: AbsolutePath

    /// Initializes the options with its attributes.
    ///
    /// - Parameters:
    ///   - buildConfiguration: build configuration.
    ///   - sourceRootPath: source root path.
    init(buildConfiguration: BuildConfiguration = .debug,
         sourceRootPath: AbsolutePath = AbsolutePath.current) {
        self.buildConfiguration = buildConfiguration
        self.sourceRootPath = sourceRootPath
    }
}
