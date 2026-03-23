import Foundation
import Testing
import TuistTesting
@testable import ProjectDescription

struct ConfigTests {
    @Test func test_config_toJSON() throws {
        let config = Config(
            generationOptions: .options(
                resolveDependenciesWithSystemScm: true,
                disablePackageVersionLocking: false,
                clonedSourcePackagesDirPath: .relativeToRoot("CustomSourcePackages"),
                staticSideEffectsWarningTargets: .excluding(["Target1", "Target2"]),
                defaultConfiguration: "Release",
                optionalAuthentication: true,
                buildInsightsDisabled: false,
                disableSandbox: true,
                includeGenerateScheme: true,
                additionalPackageResolutionArguments: ["--verbose"]
            )
        )

        #expect(try isCodableRoundTripable(config))
    }

    @Test func test_config_toJSON_with_gitPlugin() throws {
        let config = Config(
            plugins: [.git(url: "https://git.com/repo.git", tag: "1.0.0", directory: "PluginDirectory")],
            generationOptions: .options()
        )

        #expect(try isCodableRoundTripable(config))
    }

    @Test func test_config_toJSON_with_localPlugin() throws {
        let config = Config(
            plugins: [.local(path: "/some/path/to/plugin")],
            generationOptions: .options()
        )

        #expect(try isCodableRoundTripable(config))
    }

    @Test func test_config_toJSON_with_swiftVersion() throws {
        let config = Config(
            swiftVersion: "5.3.0",
            generationOptions: .options()
        )

        #expect(try isCodableRoundTripable(config))
    }
}
