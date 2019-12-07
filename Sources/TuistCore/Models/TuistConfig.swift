import Basic
import Foundation
import TuistSupport

/// This model allows to configure Tuist.
public class TuistConfig: Equatable, Hashable {
    /// Contains options related to the project generation.
    ///
    /// - generateManifestElement: When passed, Tuist generates the projects, targets and schemes to compile the project manifest.
    public enum GenerationOption: Hashable, Equatable {
        case generateManifest
        case xcodeProjectName(String)
    }

    /// Generation options.
    public let generationOptions: [GenerationOption]

    /// List of Xcode versions the project or set of projects is compatible with.
    public let compatibleXcodeVersions: CompatibleXcodeVersions

    /// Returns the default Tuist configuration.
    public static var `default`: TuistConfig {
        TuistConfig(compatibleXcodeVersions: .all,
                    generationOptions: [])
    }

    /// Initializes the tuist cofiguration.
    ///
    /// - Parameters:
    ///   - compatibleXcodeVersions: List of Xcode versions the project or set of projects is compatible with.
    ///   - generationOptions: Generation options.
    public init(compatibleXcodeVersions: CompatibleXcodeVersions,
                generationOptions: [GenerationOption]) {
        self.compatibleXcodeVersions = compatibleXcodeVersions
        self.generationOptions = generationOptions
    }

    static func at(_ path: AbsolutePath, cache: GraphLoaderCaching, modelLoader: GeneratorModelLoading) throws -> TuistConfig {
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
        lhs.generationOptions == rhs.generationOptions
    }
}

public func == (lhs: TuistConfig.GenerationOption, rhs: TuistConfig.GenerationOption) -> Bool {
    switch (lhs, rhs) {
    case let (.xcodeProjectName(lhs), .xcodeProjectName(rhs)):
        return lhs == rhs
    default: return false
    }
}
