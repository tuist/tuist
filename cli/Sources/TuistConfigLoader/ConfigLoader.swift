import FileSystem
import Foundation
import Mockable
import Path
import TuistConfig
import TuistConfigToml
import TuistConstants

@Mockable
public protocol ConfigLoading: Sendable {
    func loadConfig(path: AbsolutePath) async throws -> TuistConfig.Tuist
}

public final class ConfigLoader: ConfigLoading {
    #if os(macOS)
        private let swiftConfigLoader: SwiftConfigLoading
    #endif
    private let tomlConfigLoader: TuistTomlConfigLoading
    private let fileSystem: FileSysteming

    #if os(macOS)
        public convenience init(
            tomlConfigLoader: TuistTomlConfigLoading = TuistTomlConfigLoader(),
            fileSystem: FileSysteming = FileSystem()
        ) {
            self.init(
                swiftConfigLoader: SwiftConfigLoader(),
                tomlConfigLoader: tomlConfigLoader,
                fileSystem: fileSystem
            )
        }

        init(
            swiftConfigLoader: SwiftConfigLoading,
            tomlConfigLoader: TuistTomlConfigLoading = TuistTomlConfigLoader(),
            fileSystem: FileSysteming = FileSystem()
        ) {
            self.swiftConfigLoader = swiftConfigLoader
            self.tomlConfigLoader = tomlConfigLoader
            self.fileSystem = fileSystem
        }
    #else
        public init(
            tomlConfigLoader: TuistTomlConfigLoading = TuistTomlConfigLoader(),
            fileSystem: FileSysteming = FileSystem()
        ) {
            self.tomlConfigLoader = tomlConfigLoader
            self.fileSystem = fileSystem
        }
    #endif

    public func loadConfig(path: AbsolutePath) async throws -> TuistConfig.Tuist {
        #if os(macOS)
            if let _ = try await swiftConfigLoader.locateConfig(at: path) {
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
