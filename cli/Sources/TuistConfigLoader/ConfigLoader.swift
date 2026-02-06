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

    #if os(macOS)
        public convenience init(
            tomlConfigLoader: TuistTomlConfigLoading = TuistTomlConfigLoader()
        ) {
            self.init(
                swiftConfigLoader: SwiftConfigLoader(),
                tomlConfigLoader: tomlConfigLoader
            )
        }

        init(
            swiftConfigLoader: SwiftConfigLoading,
            tomlConfigLoader: TuistTomlConfigLoading = TuistTomlConfigLoader()
        ) {
            self.swiftConfigLoader = swiftConfigLoader
            self.tomlConfigLoader = tomlConfigLoader
        }
    #else
        public init(
            tomlConfigLoader: TuistTomlConfigLoading = TuistTomlConfigLoader()
        ) {
            self.tomlConfigLoader = tomlConfigLoader
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

        return .default
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
}
