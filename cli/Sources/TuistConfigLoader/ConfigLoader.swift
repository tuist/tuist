import FileSystem
import Foundation
import Mockable
import Path
import TuistConfig
import TuistConstants
import TuistEnvironment
import TuistHTTP
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

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
        let config = try await resolveConfig(at: path)
        applyProxy(from: config)
        return config
    }

    private func resolveConfig(at path: AbsolutePath) async throws -> TuistConfig.Tuist {
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

    /// Resolves the user-configured proxy against the current environment and applies
    /// the resulting URL to the shared `URLSession`. Runs regardless of whether the
    /// config came from `Tuist.swift` or `tuist.toml`, so both code paths route their
    /// network traffic through the same proxy.
    private func applyProxy(from config: TuistConfig.Tuist) {
        let proxyURL = config.proxy.resolvedURL(environment: Environment.current.variables)
        URLSession.configureTuistProxy(proxyURL)
    }

    private func configFromToml(_ tomlConfig: TuistTomlConfig) -> TuistConfig.Tuist {
        let proxy: TuistConfig.Tuist.Proxy = tomlConfig.proxy?.toTuistConfigProxy().proxy ?? .none
        return TuistConfig.Tuist(
            project: .defaultGeneratedProject(),
            fullHandle: tomlConfig.project,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: tomlConfig.url ?? Constants.URLs.production,
            proxy: proxy
        )
    }
}
