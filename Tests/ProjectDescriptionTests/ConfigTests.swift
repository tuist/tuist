import Foundation
import XCTest
@testable import ProjectDescription

final class ConfigTests: XCTestCase {
    func test_config_toJSON() throws {
        let config = Config(
            cloud: Cloud(url: "https://cloud.tuist.io", projectId: "123", options: [.analytics]),
            generationOptions: .options(
                xcodeProjectName: "someprefix-\(.projectName)",
                organizationName: "TestOrg",
                developmentRegion: "de",
                disableShowEnvironmentVarsInScriptPhases: true,
                resolveDependenciesWithSystemScm: false,
                disablePackageVersionLocking: true, lastXcodeUpgradeCheck: .init(12, 5, 1)
            )
        )

        XCTAssertCodable(config)
    }

    func test_config_toJSON_with_gitPlugin() {
        let config = Config(
            plugins: [.git(url: "https://git.com/repo.git", tag: "1.0.0")],
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
