import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistConfig
import TuistConstants
import TuistHTTP

@testable import TuistConfigLoader

@Suite(.serialized)
struct ConfigLoaderTests {
    @Test(.inTemporaryDirectory)
    func loadConfig_returns_toml_config_when_toml_exists() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlConfigLoader = MockTuistTomlConfigLoading()
        let previousSettings = HTTPSettings.current
        defer { HTTPSettings.current = previousSettings }

        given(tomlConfigLoader)
            .loadConfig(at: .any)
            .willReturn(TuistTomlConfig(
                project: "tuist/tuist",
                url: URL(string: "https://custom.tuist.dev")!,
                network: .init(proxy: false)
            ))

        let subject = makeConfigLoader(tomlConfigLoader: tomlConfigLoader)

        let config = try await subject.loadConfig(path: temporaryDirectory)

        #expect(config.fullHandle == "tuist/tuist")
        #expect(config.url == URL(string: "https://custom.tuist.dev")!)
        #expect(config.network.proxy == false)
        #expect(HTTPSettings.current.useEnvironmentProxy == false)
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_uses_production_url_when_toml_has_no_url() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlConfigLoader = MockTuistTomlConfigLoading()
        let previousSettings = HTTPSettings.current
        defer { HTTPSettings.current = previousSettings }

        given(tomlConfigLoader)
            .loadConfig(at: .any)
            .willReturn(TuistTomlConfig(project: "org/project"))

        let subject = makeConfigLoader(tomlConfigLoader: tomlConfigLoader)

        let config = try await subject.loadConfig(path: temporaryDirectory)

        #expect(config.fullHandle == "org/project")
        #expect(config.url == Constants.URLs.production)
        #expect(config.network.proxy == true)
        #expect(HTTPSettings.current.useEnvironmentProxy == true)
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_returns_toml_network_config_without_project() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlConfigLoader = MockTuistTomlConfigLoading()
        let previousSettings = HTTPSettings.current
        defer { HTTPSettings.current = previousSettings }

        given(tomlConfigLoader)
            .loadConfig(at: .any)
            .willReturn(TuistTomlConfig(network: .init(proxy: false)))

        let subject = makeConfigLoader(tomlConfigLoader: tomlConfigLoader)

        let config = try await subject.loadConfig(path: temporaryDirectory)

        #expect(config.fullHandle == nil)
        #expect(config.url == Constants.URLs.production)
        #expect(config.network.proxy == false)
        #expect(HTTPSettings.current.useEnvironmentProxy == false)
    }

    private func makeConfigLoader(tomlConfigLoader: TuistTomlConfigLoading) -> ConfigLoader {
        #if os(macOS)
            let swiftConfigLoader = MockSwiftConfigLoading()
            given(swiftConfigLoader).locateConfig(at: .any).willReturn(nil)
            return ConfigLoader(swiftConfigLoader: swiftConfigLoader, tomlConfigLoader: tomlConfigLoader)
        #else
            return ConfigLoader(tomlConfigLoader: tomlConfigLoader)
        #endif
    }
}
