import FileSystem
import Foundation
import Mockable
import Path
import TuistConfig
import TuistConstants

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
                return try await swiftConfigLoader.loadConfig(path: path)
            }
        #endif

        if let tomlConfig = try await tomlConfigLoader.loadConfig(at: path) {
            return configFromToml(tomlConfig)
        }

        return .default
    }

    private func configFromToml(_ tomlConfig: TuistTomlConfig) -> TuistConfig.Tuist {
        TuistConfig.Tuist(
            project: .defaultGeneratedProject(),
            fullHandle: tomlConfig.project,
            inspectOptions: .init(redundantDependencies: .init(ignoreTagsMatching: [])),
            url: tomlConfig.url ?? Constants.URLs.production
        )
    }
}
