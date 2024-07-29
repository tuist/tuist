import Foundation
import Mockable
import Path
import struct ProjectDescription.Config
import TuistCore
import TuistSupport
import XcodeGraph

@Mockable
public protocol ConfigLoading {
    /// Loads the Tuist configuration by traversing the file system till the Config manifest is found,
    /// otherwise returns the default configuration.
    ///
    /// - Parameter path: Directory from which look up and load the Config.
    /// - Returns: Loaded Config object.
    /// - Throws: An error if the Config.swift can't be parsed.
    func loadConfig(path: AbsolutePath) async throws -> TuistCore.Config

    /// Locates the Config.swift manifest from the given directory.
    func locateConfig(at: AbsolutePath) -> AbsolutePath?
}

public final class ConfigLoader: ConfigLoading {
    private let manifestLoader: ManifestLoading
    private let rootDirectoryLocator: RootDirectoryLocating
    private let fileHandler: FileHandling
    private var cachedConfigs: [AbsolutePath: TuistCore.Config] = [:]

    public init(
        manifestLoader: ManifestLoading = ManifestLoader(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        fileHandler: FileHandling = FileHandler.shared
    ) {
        self.manifestLoader = manifestLoader
        self.rootDirectoryLocator = rootDirectoryLocator
        self.fileHandler = fileHandler
    }

    public func loadConfig(path: AbsolutePath) async throws -> TuistCore.Config {
        if let cached = cachedConfigs[path] {
            return cached
        }

        guard let configPath = locateConfig(at: path) else {
            let config = TuistCore.Config.default
            cachedConfigs[path] = config
            return config
        }

        let manifest = try await manifestLoader.loadConfig(at: configPath.parentDirectory)
        let config = try TuistCore.Config.from(manifest: manifest, at: configPath)
        cachedConfigs[path] = config
        return config
    }

    public func locateConfig(at path: AbsolutePath) -> AbsolutePath? {
        // If the Config.swift file exists in the root Tuist/ directory, we load it from there
        if let rootDirectoryPath = rootDirectoryLocator.locate(from: path) {
            // swiftlint:disable:next force_try
            let relativePath = try! RelativePath(validating: "\(Constants.tuistDirectoryName)/\(Manifest.config.fileName(path))")
            let configPath = rootDirectoryPath.appending(relativePath)
            if fileHandler.exists(configPath) {
                return configPath
            }
        }

        // Otherwise we try to traverse up the directories to find it
        return fileHandler.locateDirectoryTraversingParents(from: path, path: Manifest.config.fileName(path))
    }
}
