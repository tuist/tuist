import FileSystem
import Foundation
import Mockable
import Path
import struct ProjectDescription.Config
import ServiceContextModule
import TuistCore
import TuistSupport

@Mockable
public protocol ConfigLoading {
    /// Loads the Tuist configuration by traversing the file system till the Config manifest is found,
    /// otherwise returns the default configuration.
    ///
    /// - Parameter path: Directory from which look up and load the Config.
    /// - Returns: Loaded Config object.
    /// - Throws: An error if the Tuist.swift can't be parsed.
    func loadConfig(path: AbsolutePath) async throws -> TuistCore.Config

    /// Locates the Tuist.swift manifest from the given directory.
    func locateConfig(at: AbsolutePath) async throws -> AbsolutePath?
}

public final class ConfigLoader: ConfigLoading {
    private let manifestLoader: ManifestLoading
    private let rootDirectoryLocator: RootDirectoryLocating
    private let fileSystem: FileSysteming
    private var cachedConfigs: [AbsolutePath: TuistCore.Config] = [:]
    public init(
        manifestLoader: ManifestLoading = ManifestLoader(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.manifestLoader = manifestLoader
        self.rootDirectoryLocator = rootDirectoryLocator
        self.fileSystem = fileSystem
    }

    public func loadConfig(path: AbsolutePath) async throws -> TuistCore.Config {
        if let cached = cachedConfigs[path] {
            return cached
        }

        guard let configPath = try await locateConfig(at: path) else {
            let config = TuistCore.Config.default
            cachedConfigs[path] = config
            return config
        }

        if configPath.pathString.contains("Config.swift") {
            ServiceContext.current?.alerts?
                .append(
                    .warning(.alert("Tuist/Config.swift is deprecated. Rename Tuist/Config.swift to Tuist.swift at the root."))
                )
        }

        let manifest = try await manifestLoader.loadConfig(at: configPath.parentDirectory)
        let rootDirectory: AbsolutePath = try await rootDirectoryLocator.locate(from: configPath)
        let config = try await TuistCore.Config.from(
            manifest: manifest,
            rootDirectory: rootDirectory,
            at: configPath
        )
        cachedConfigs[path] = config
        return config
    }

    public func locateConfig(at path: AbsolutePath) async throws -> AbsolutePath? {
        if let rootDirectoryPath = try await rootDirectoryLocator.locate(from: path) {
            for candidate in [
                rootDirectoryPath
                    .appending(
                        // swiftlint:disable:next force_try
                        try! RelativePath(validating: "\(Constants.tuistDirectoryName)/\(Manifest.config.fileName(path))")
                    ),
                // swiftlint:disable:next force_try
                rootDirectoryPath.appending(try! RelativePath(validating: Constants.tuistManifestFileName)),
            ] {
                if try await fileSystem.exists(candidate) {
                    return candidate
                }
            }
        }
        return nil
    }
}
