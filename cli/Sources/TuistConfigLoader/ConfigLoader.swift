import FileSystem
import Foundation
import Mockable
import Path
import TuistConfig
import TuistConstants
import TuistEnvironment
import TuistHTTP

@Mockable
public protocol ConfigLoading: Sendable {
    func loadConfig(path: AbsolutePath) async throws -> TuistConfig.Tuist
}

public struct ConfigLoader: ConfigLoading {
    #if os(macOS)
        private let swiftConfigLoader: SwiftConfigLoading
    #endif
    private let tomlConfigLoader: TuistTomlConfigLoading

    public init() {
        #if os(macOS)
            swiftConfigLoader = SwiftConfigLoader()
        #endif
        tomlConfigLoader = TuistTomlConfigLoader()
    }

    #if os(macOS)
        init(
            swiftConfigLoader: SwiftConfigLoading,
            tomlConfigLoader: TuistTomlConfigLoading = TuistTomlConfigLoader()
        ) {
            self.swiftConfigLoader = swiftConfigLoader
            self.tomlConfigLoader = tomlConfigLoader
        }
    #else
        init(
            tomlConfigLoader: TuistTomlConfigLoading
        ) {
            self.tomlConfigLoader = tomlConfigLoader
        }
    #endif

    public func loadConfig(path: AbsolutePath) async throws -> TuistConfig.Tuist {
        #if os(macOS)
            if let _ = try await swiftConfigLoader.locateConfig(at: path) {
                let config = try await swiftConfigLoader.loadConfig(path: path)
                applyRuntimeSettings(from: config)
                return config
            }
        #endif

        if let tomlConfig = try await tomlConfigLoader.loadConfig(at: path) {
            let config = configFromToml(tomlConfig)
            applyRuntimeSettings(from: config)
            return config
        }

        applyRuntimeSettings(from: .default)
        return .default
    }

    private func configFromToml(_ tomlConfig: TuistTomlConfig) -> TuistConfig.Tuist {
        return TuistConfig.Tuist(
            project: .defaultGeneratedProject(),
            fullHandle: tomlConfig.project,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: tomlConfig.url ?? Constants.URLs.production,
            network: .init(proxy: tomlConfig.http?.proxy ?? true)
        )
    }

    private func applyRuntimeSettings(from config: TuistConfig.Tuist) {
        HTTPSettings.current = .init(useEnvironmentProxy: config.network.proxy)
    }
}
