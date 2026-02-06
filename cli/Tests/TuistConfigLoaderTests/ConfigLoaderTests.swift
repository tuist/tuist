import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistConfig
import TuistConstants

@testable import TuistConfigLoader

struct ConfigLoaderTests {
    @Test(.inTemporaryDirectory)
    func loadConfig_returns_toml_config_when_toml_exists() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlConfigLoader = MockTuistTomlConfigLoading()

        given(tomlConfigLoader)
            .loadConfig(at: .any)
            .willReturn(TuistTomlConfig(project: "tuist/tuist", url: URL(string: "https://custom.tuist.dev")!))

        let subject = makeConfigLoader(tomlConfigLoader: tomlConfigLoader)

        let config = try await subject.loadConfig(path: temporaryDirectory)

        #expect(config.fullHandle == "tuist/tuist")
        #expect(config.url == URL(string: "https://custom.tuist.dev")!)
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_uses_production_url_when_toml_has_no_url() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlConfigLoader = MockTuistTomlConfigLoading()

        given(tomlConfigLoader)
            .loadConfig(at: .any)
            .willReturn(TuistTomlConfig(project: "org/project"))

        let subject = makeConfigLoader(tomlConfigLoader: tomlConfigLoader)

        let config = try await subject.loadConfig(path: temporaryDirectory)

        #expect(config.fullHandle == "org/project")
        #expect(config.url == Constants.URLs.production)
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
