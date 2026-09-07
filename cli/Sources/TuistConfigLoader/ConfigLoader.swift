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
    private let swiftConfigLoader: SwiftConfigLoading
    private let tomlConfigLoader: TuistTomlConfigLoading

    public init() {
        swiftConfigLoader = SwiftConfigLoader()
        tomlConfigLoader = TuistTomlConfigLoader()
    }

    init(
        swiftConfigLoader: SwiftConfigLoading,
        tomlConfigLoader: TuistTomlConfigLoading = TuistTomlConfigLoader()
    ) {
        self.swiftConfigLoader = swiftConfigLoader
        self.tomlConfigLoader = tomlConfigLoader
    }

    public func loadConfig(path: AbsolutePath) async throws -> TuistConfig.Tuist {
        if let _ = try await swiftConfigLoader.locateConfig(at: path) {
            let config = try await swiftConfigLoader.loadConfig(path: path)
            applyRuntimeSettings(from: config)
            return config
        }

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
            network: .init(
                proxy: tomlConfig.network?.proxy ?? true,
                caCertificate: tomlConfig.network?.caCertificate
            )
        )
    }

    private func applyRuntimeSettings(from config: TuistConfig.Tuist) {
        HTTPSettings.current = .init(
            useEnvironmentProxy: config.network.proxy,
            caCertificatePath: config.network.caCertificate
        )
    }
}
