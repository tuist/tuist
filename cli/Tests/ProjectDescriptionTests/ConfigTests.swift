import Foundation
import XCTest
@testable import ProjectDescription

final class ConfigTests: XCTestCase {
    func test_config_toJSON() {
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

        XCTAssertCodable(config)
    }

    func test_config_toJSON_with_gitPlugin() {
        let config = Config(
            plugins: [.git(url: "https://git.com/repo.git", tag: "1.0.0", directory: "PluginDirectory")],
            generationOptions: .options()
        )

        XCTAssertCodable(config)
    }

    func test_config_toJSON_with_localPlugin() {
        let config = Config(
            plugins: [.local(path: "/some/path/to/plugin")],
            generationOptions: .options()
        )

        XCTAssertCodable(config)
    }

    func test_config_toJSON_with_swiftVersion() {
        let config = Config(
            swiftVersion: "5.3.0",
            generationOptions: .options()
        )

        XCTAssertCodable(config)
    }
}
