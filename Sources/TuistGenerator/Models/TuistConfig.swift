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
        return TuistConfig(generationOptions: [])
    }

    /// Initializes the tuist cofiguration.
    ///
    /// - Parameters:
    ///   - generationOptions: Generation options.
    public init(generationOptions: [GenerationOption]) {
        self.generationOptions = generationOptions
    }

    static func at(_ path: AbsolutePath, cache: GraphLoaderCaching, modelLoader: GeneratorModelLoading, fileHandler: FileHandling) throws -> TuistConfig {
        guard let tuistConfigPath = locateDirectoryTraversingParents(from: path, path: "TuistConfig.swift", fileHandler: fileHandler) else {
            return .default
        }

        /// Directory that contains the TuistConfig.swift
        let path = tuistConfigPath.parentDirectory

        if let tuistConfig = cache.tuistConfig(path) {
            return tuistConfig
        } else {
            let tuistConfig = try modelLoader.loadTuistConfig(at: path)
            cache.add(tuistConfig: tuistConfig, path: path)
            return tuistConfig
        }
    }

    // MARK: - Fileprivate

    /// Traverses the parent directories until the given path is found.
    ///
    /// - Parameters:
    ///   - from: A path to a directory from which search the TuistConfig.swift.
    ///   - fileHandler: An instance to interact with the file system.
    /// - Returns: The found path.
    fileprivate static func locateDirectoryTraversingParents(from: AbsolutePath, path: String, fileHandler: FileHandling) -> AbsolutePath? {
        let tuistConfigPath = from.appending(component: path)

        if fileHandler.exists(tuistConfigPath) {
            return tuistConfigPath
        } else if from == AbsolutePath("/") {
            return nil
        } else {
            return locateDirectoryTraversingParents(from: from.parentDirectory, path: path, fileHandler: fileHandler)
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
