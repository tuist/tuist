import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistConfig
import TuistConfigToml
import TuistConstants
import TuistRootDirectoryLocator

@testable import TuistConfigLoader

struct ConfigLoaderTests {
    private let fileSystem = FileSystem()

    @Test(.inTemporaryDirectory)
    func loadConfig_returns_toml_config_when_toml_exists() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlConfigLoader = MockTuistTomlConfigLoading()
        let rootDirectoryLocator = MockRootDirectoryLocating()

        given(tomlConfigLoader)
            .loadConfig(at: .any)
            .willReturn(TuistTomlConfig(project: "tuist/tuist", url: "https://custom.tuist.dev"))

        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(temporaryDirectory)

        let subject = ConfigLoader(
            tomlConfigLoader: tomlConfigLoader,
            rootDirectoryLocator: rootDirectoryLocator,
            fileSystem: fileSystem
        )

        let config = try await subject.loadConfig(path: temporaryDirectory)

        #expect(config.fullHandle == "tuist/tuist")
        #expect(config.url == URL(string: "https://custom.tuist.dev")!)
    }

    @Test(.inTemporaryDirectory)
    func loadConfig_uses_production_url_when_toml_has_no_url() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let tomlConfigLoader = MockTuistTomlConfigLoading()
        let rootDirectoryLocator = MockRootDirectoryLocating()

        given(tomlConfigLoader)
            .loadConfig(at: .any)
            .willReturn(TuistTomlConfig(project: "org/project"))

        given(rootDirectoryLocator)
            .locate(from: .any)
            .willReturn(temporaryDirectory)

        let subject = ConfigLoader(
            tomlConfigLoader: tomlConfigLoader,
            rootDirectoryLocator: rootDirectoryLocator,
            fileSystem: fileSystem
        )

        let config = try await subject.loadConfig(path: temporaryDirectory)

        #expect(config.fullHandle == "org/project")
        #expect(config.url == Constants.URLs.production)
    }
}
