import FileSystem
import Foundation
import Mockable
import Path
import struct ProjectDescription.Config
import TuistCore
import TuistRootDirectoryLocator
import TuistSupport

@Mockable
public protocol ConfigLoading {
    /// Loads the Tuist configuration by traversing the file system till the Config manifest is found,
    /// otherwise returns the default configuration.
    ///
    /// - Parameter path: Directory from which look up and load the Config.
    /// - Returns: Loaded Config object.
    /// - Throws: An error if the Tuist.swift can't be parsed.
    func loadConfig(path: AbsolutePath) async throws -> TuistCore.Tuist

    /// Locates the Tuist.swift manifest from the given directory.
    func locateConfig(at: AbsolutePath) async throws -> AbsolutePath?
}

public final class ConfigLoader: ConfigLoading {
    private let manifestLoader: ManifestLoading
    private let rootDirectoryLocator: RootDirectoryLocating
    private let fileSystem: FileSysteming
    private var cachedConfigs: [AbsolutePath: TuistCore.Tuist] = [:]
    public init(
        manifestLoader: ManifestLoading = CachedManifestLoader(),
        rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.manifestLoader = manifestLoader
        self.rootDirectoryLocator = rootDirectoryLocator
        self.fileSystem = fileSystem
    }

    public func loadConfig(path: AbsolutePath) async throws -> TuistCore.Tuist {
        if let cached = cachedConfigs[path] {
            return cached
        }

        guard let configPath = try await locateConfig(at: path) else {
            let config = try await defaultConfig(at: path)
            cachedConfigs[path] = config
            return config
        }

        if configPath.pathString.contains("Config.swift") {
            AlertController.current
                .warning(.alert("Tuist/Config.swift is deprecated. Rename Tuist/Config.swift to Tuist.swift at the root."))
        }

        let manifest = try await manifestLoader.loadConfig(at: configPath.parentDirectory)
        let rootDirectory: AbsolutePath = try await rootDirectoryLocator.locate(from: configPath)
        let config = try await TuistCore.Tuist.from(
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

    private func defaultConfig(at path: AbsolutePath) async throws -> Tuist {
        let anyXcodeProjectOrWorkspace = !(
            try await fileSystem.glob(directory: path, include: ["*.xcodeproj", "*.xcworkspace"])
                .collect().isEmpty
        )
        let anyWorkspaceOrProjectManifest = !(try await fileSystem.glob(
            directory: path,
            include: ["Project.swift", "Workspace.swift"]
        ).collect().isEmpty)

        let anyPackageSwift = !(
            try await fileSystem.glob(directory: path, include: ["Package.swift"])
                .collect().isEmpty
        )

        if anyPackageSwift, !anyWorkspaceOrProjectManifest {
            return Tuist(
                project: .swiftPackage(TuistSwiftPackageOptions()),
                fullHandle: nil,
                inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
                url: Constants.URLs.production
            )
        } else if anyXcodeProjectOrWorkspace, !anyWorkspaceOrProjectManifest {
            return Tuist(
                project: .xcode(TuistXcodeProjectOptions()),
                fullHandle: nil,
                inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
                url: Constants.URLs.production
            )
        } else {
            return TuistCore.Tuist.default
        }
    }
}
