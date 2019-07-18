import Basic
import Foundation
import TuistCore

/// This model allows to configure Tuist.
public class TuistConfig: Equatable, Hashable {
    /// Contains options related to the project generation.
    ///
    /// - generateManifestElement: When passed, Tuist generates the projects, targets and schemes to compile the project manifest.
    public enum GenerationOption: String, Codable, Equatable, Hashable {
        case generateManifestElements
    }

    /// Generation options.
    public let generationOptions: [GenerationOption]

    /// Returns the default Tuist configuration.
    public static var `default`: TuistConfig {
        return TuistConfig(generationOptions: [.generateManifestElements])
    }

    /// Initializes the tuist cofiguration.
    ///
    /// - Parameters:
    ///   - generationOptions: Generation options.
    public init(generationOptions: [GenerationOption]) {
        self.generationOptions = generationOptions
    }

    static func at(_ path: AbsolutePath, cache: GraphLoaderCaching, modelLoader: GeneratorModelLoading, fileHandler _: FileHandling) throws -> TuistConfig {
        if let tuistConfig = cache.tuistConfig(path) {
            return tuistConfig
        } else {
            let tuistConfig = try modelLoader.loadTuistConfig(at: path)
            cache.add(tuistConfig: tuistConfig, path: path)
            return tuistConfig
        }
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(generationOptions)
    }

    // MARK: - Equatable

    public static func == (lhs: TuistConfig, rhs: TuistConfig) -> Bool {
        return lhs.generationOptions == rhs.generationOptions
    }
}
