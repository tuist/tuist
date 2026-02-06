import FileSystem
import Foundation
import Mockable
import Path
import TuistConfig
import TuistConfigToml
import TuistConstants
import TuistRootDirectoryLocator

#if os(macOS)
    @preconcurrency import TuistLoader
#endif

@Mockable
public protocol ConfigLoading: Sendable {
    func loadConfig(path: AbsolutePath) async throws -> TuistConfig.Tuist
}

public final class ConfigLoader: ConfigLoading {
    #if os(macOS)
        private let swiftConfigLoader: TuistLoader.ConfigLoading
    #endif
    private let tomlConfigLoader: TuistTomlConfigLoading
    private let rootDirectoryLocator: RootDirectoryLocating
    private let fileSystem: FileSysteming

    #if os(macOS)
        public init(
            swiftConfigLoader: TuistLoader.ConfigLoading = TuistLoader.ConfigLoader(),
            tomlConfigLoader: TuistTomlConfigLoading = TuistTomlConfigLoader(),
            rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
            fileSystem: FileSysteming = FileSystem()
        ) {
            self.swiftConfigLoader = swiftConfigLoader
            self.tomlConfigLoader = tomlConfigLoader
            self.rootDirectoryLocator = rootDirectoryLocator
            self.fileSystem = fileSystem
        }
    #else
        public init(
            tomlConfigLoader: TuistTomlConfigLoading = TuistTomlConfigLoader(),
            rootDirectoryLocator: RootDirectoryLocating = RootDirectoryLocator(),
            fileSystem: FileSysteming = FileSystem()
        ) {
            self.tomlConfigLoader = tomlConfigLoader
            self.rootDirectoryLocator = rootDirectoryLocator
            self.fileSystem = fileSystem
        }
    #endif

    public func loadConfig(path: AbsolutePath) async throws -> TuistConfig.Tuist {
        #if os(macOS)
            if try await hasSwiftConfig(at: path) {
                return try await swiftConfigLoader.loadConfig(path: path)
            }
        #endif

        if let tomlConfig = try await tomlConfigLoader.loadConfig(at: path) {
            return configFromToml(tomlConfig)
        }

        #if os(macOS)
            return try await swiftConfigLoader.loadConfig(path: path)
        #else
            return try await defaultConfig(at: path)
        #endif
    }

    #if os(macOS)
        private func hasSwiftConfig(at path: AbsolutePath) async throws -> Bool {
            guard let rootDirectoryPath = try await rootDirectoryLocator.locate(from: path) else {
                return false
            }
            for candidate in [
                rootDirectoryPath
                    .appending(
                        // swiftlint:disable:next force_try
                        try! RelativePath(validating: "\(Constants.tuistDirectoryName)/Config.swift")
                    ),
                // swiftlint:disable:next force_try
                rootDirectoryPath.appending(try! RelativePath(validating: Constants.tuistManifestFileName)),
            ] {
                if try await fileSystem.exists(candidate) {
                    return true
                }
            }
            return false
        }
    #endif

    private func configFromToml(_ tomlConfig: TuistTomlConfig) -> TuistConfig.Tuist {
        let url: URL
        if let urlString = tomlConfig.url, let parsedURL = URL(string: urlString) {
            url = parsedURL
        } else {
            url = Constants.URLs.production
        }

        return TuistConfig.Tuist(
            project: .defaultGeneratedProject(),
            fullHandle: tomlConfig.project,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: url
        )
    }

    #if !os(macOS)
        private func defaultConfig(at path: AbsolutePath) async throws -> TuistConfig.Tuist {
            let anyPackageSwift = !(
                try await fileSystem.glob(directory: path, include: ["Package.swift"])
                    .collect().isEmpty
            )
            if anyPackageSwift {
                return TuistConfig.Tuist(
                    project: .swiftPackage(TuistSwiftPackageOptions()),
                    fullHandle: nil,
                    inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
                    url: Constants.URLs.production
                )
            } else {
                return TuistConfig.Tuist.default
            }
        }
    #endif
}
