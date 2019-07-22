import Foundation

/// This model allows to configure Tuist.
public class TuistConfig: Codable {
    /// Contains options related to the project generation.
    ///
    /// - generateManifestElement: When passed, Tuist generates the projects, targets and schemes to compile the project manifest.
    public enum GenerationOption: String, Codable {
        case generateManifest
    }

    /// Generation options.
    public let generationOptions: [GenerationOption]

    /// Initializes the tuist cofiguration.
    ///
    /// - Parameter generationOptions: Generation options.
    public init(generationOptions: [GenerationOption]) {
        self.generationOptions = generationOptions
        dumpIfNeeded(self)
    }
}
