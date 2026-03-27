import Foundation
import Testing

@testable import TuistKit

struct ShardServiceTests {
    let subject = ShardService()

    @Test
    func filterXCTestRun_filtersToSpecifiedModules() throws {
        // Given
        let plistData = try makePlist([
            "TestConfigurations": [
                [
                    "TestTargets": [
                        ["BlueprintName": "AppTests", "TestHostPath": "/path/to/host"],
                        ["BlueprintName": "CoreTests", "TestHostPath": "/path/to/core"],
                        ["BlueprintName": "UITests", "TestHostPath": "/path/to/ui"],
                    ],
                ],
            ],
        ])

        // When
        let filtered = try subject.filterXCTestRun(
            plistData: plistData,
            modules: ["AppTests", "UITests"],
            suites: [:]
        )

        // Then
        let result = try parsePlist(filtered)
        let targets = blueprintNames(from: result)
        #expect(targets == ["AppTests", "UITests"])
    }

    @Test
    func filterXCTestRun_injectsOnlyTestIdentifiersForSuites() throws {
        // Given
        let plistData = try makePlist([
            "TestConfigurations": [
                [
                    "TestTargets": [
                        ["BlueprintName": "AppTests"],
                        ["BlueprintName": "CoreTests"],
                    ],
                ],
            ],
        ])

        // When
        let filtered = try subject.filterXCTestRun(
            plistData: plistData,
            modules: ["AppTests", "CoreTests"],
            suites: ["AppTests": ["LoginTests", "SignupTests"], "CoreTests": ["NetworkTests"]]
        )

        // Then
        let result = try parsePlist(filtered)
        let configurations = result["TestConfigurations"] as! [[String: Any]]
        let targets = configurations[0]["TestTargets"] as! [[String: Any]]

        let appTarget = targets.first { $0["BlueprintName"] as? String == "AppTests" }!
        #expect(appTarget["OnlyTestIdentifiers"] as? [String] == ["LoginTests", "SignupTests"])

        let coreTarget = targets.first { $0["BlueprintName"] as? String == "CoreTests" }!
        #expect(coreTarget["OnlyTestIdentifiers"] as? [String] == ["NetworkTests"])
    }

    @Test
    func filterXCTestRun_preservesOtherFields() throws {
        // Given
        let plistData = try makePlist([
            "TestConfigurations": [
                [
                    "TestTargets": [
                        [
                            "BlueprintName": "AppTests",
                            "TestHostPath": "/path/to/host",
                            "EnvironmentVariables": ["KEY": "VALUE"],
                        ],
                    ],
                ],
            ],
        ])

        // When
        let filtered = try subject.filterXCTestRun(
            plistData: plistData,
            modules: ["AppTests"],
            suites: [:]
        )

        // Then
        let result = try parsePlist(filtered)
        let configurations = result["TestConfigurations"] as! [[String: Any]]
        let target = (configurations[0]["TestTargets"] as! [[String: Any]])[0]
        #expect(target["TestHostPath"] as? String == "/path/to/host")
        #expect((target["EnvironmentVariables"] as? [String: String])?["KEY"] == "VALUE")
    }

    @Test
    func filterXCTestRun_multipleConfigurations() throws {
        // Given
        let plistData = try makePlist([
            "TestConfigurations": [
                [
                    "TestTargets": [
                        ["BlueprintName": "UnitTests"],
                        ["BlueprintName": "IntegrationTests"],
                    ],
                ],
                [
                    "TestTargets": [
                        ["BlueprintName": "UITests"],
                    ],
                ],
            ],
        ])

        // When
        let filtered = try subject.filterXCTestRun(
            plistData: plistData,
            modules: ["UnitTests"],
            suites: [:]
        )

        // Then
        let result = try parsePlist(filtered)
        let configurations = result["TestConfigurations"] as! [[String: Any]]
        let firstTargets = blueprintNames(fromConfig: configurations[0])
        let secondTargets = blueprintNames(fromConfig: configurations[1])
        #expect(firstTargets == ["UnitTests"])
        #expect(secondTargets.isEmpty)
    }

    @Test
    func filterXCTestRun_doesNotInjectIdentifiersWhenSuitesEmpty() throws {
        // Given
        let plistData = try makePlist([
            "TestConfigurations": [
                [
                    "TestTargets": [
                        ["BlueprintName": "AppTests"],
                    ],
                ],
            ],
        ])

        // When
        let filtered = try subject.filterXCTestRun(
            plistData: plistData,
            modules: ["AppTests"],
            suites: [:]
        )

        // Then
        let result = try parsePlist(filtered)
        let configurations = result["TestConfigurations"] as! [[String: Any]]
        let target = (configurations[0]["TestTargets"] as! [[String: Any]])[0]
        #expect(target["OnlyTestIdentifiers"] == nil)
    }

    // MARK: - Legacy Format (v1)

    @Test
    func filterXCTestRun_legacyFormat_filtersToSpecifiedModules() throws {
        // Given
        let plistData = try makePlist([
            "__xctestrun_metadata__": ["FormatVersion": 1],
            "AppTests": ["BlueprintName": "AppTests", "TestHostPath": "/path/to/host"],
            "CoreTests": ["BlueprintName": "CoreTests", "TestHostPath": "/path/to/core"],
            "UITests": ["BlueprintName": "UITests", "TestHostPath": "/path/to/ui"],
        ])

        // When
        let filtered = try subject.filterXCTestRun(
            plistData: plistData,
            modules: ["AppTests", "UITests"],
            suites: [:]
        )

        // Then
        let result = try parsePlist(filtered)
        #expect(result["AppTests"] != nil)
        #expect(result["UITests"] != nil)
        #expect(result["CoreTests"] == nil)
        #expect(result["__xctestrun_metadata__"] != nil)
    }

    @Test
    func filterXCTestRun_legacyFormat_injectsOnlyTestIdentifiers() throws {
        // Given
        let plistData = try makePlist([
            "__xctestrun_metadata__": ["FormatVersion": 1],
            "AppTests": ["BlueprintName": "AppTests"],
            "CoreTests": ["BlueprintName": "CoreTests"],
        ])

        // When
        let filtered = try subject.filterXCTestRun(
            plistData: plistData,
            modules: ["AppTests", "CoreTests"],
            suites: ["AppTests": ["LoginTests", "SignupTests"]]
        )

        // Then
        let result = try parsePlist(filtered)
        let appTarget = result["AppTests"] as! [String: Any]
        #expect(appTarget["OnlyTestIdentifiers"] as? [String] == ["LoginTests", "SignupTests"])
        let coreTarget = result["CoreTests"] as! [String: Any]
        #expect(coreTarget["OnlyTestIdentifiers"] == nil)
    }

    @Test
    func filterXCTestRun_legacyFormat_preservesOtherFields() throws {
        // Given
        let plistData = try makePlist([
            "__xctestrun_metadata__": ["FormatVersion": 1],
            "AppTests": [
                "BlueprintName": "AppTests",
                "TestHostPath": "/path/to/host",
                "EnvironmentVariables": ["KEY": "VALUE"],
            ],
        ])

        // When
        let filtered = try subject.filterXCTestRun(
            plistData: plistData,
            modules: ["AppTests"],
            suites: [:]
        )

        // Then
        let result = try parsePlist(filtered)
        let target = result["AppTests"] as! [String: Any]
        #expect(target["TestHostPath"] as? String == "/path/to/host")
        #expect((target["EnvironmentVariables"] as? [String: String])?["KEY"] == "VALUE")
    }

    // MARK: - Suite Granularity

    @Test
    func filterXCTestRun_suiteGranularity_keepsModuleAndSetsOnlyTestIdentifiers() throws {
        // Given: one module with multiple suites, shard assigned specific suites
        let plistData = try makePlist([
            "TestConfigurations": [
                [
                    "TestTargets": [
                        ["BlueprintName": "TuistGeneratorAcceptanceTests", "TestHostPath": "/path"],
                    ],
                ],
            ],
        ])

        // When: modules contains the module name, suites maps module to assigned classes
        let filtered = try subject.filterXCTestRun(
            plistData: plistData,
            modules: ["TuistGeneratorAcceptanceTests"],
            suites: ["TuistGeneratorAcceptanceTests": [
                "GenerateAcceptanceTestAppWithMacBundle",
                "GenerateAcceptanceTestSPMPackage",
            ]]
        )

        // Then: module kept, OnlyTestIdentifiers set to assigned suites
        let result = try parsePlist(filtered)
        let configurations = result["TestConfigurations"] as! [[String: Any]]
        let targets = configurations[0]["TestTargets"] as! [[String: Any]]
        #expect(targets.count == 1)
        #expect(targets[0]["BlueprintName"] as? String == "TuistGeneratorAcceptanceTests")
        #expect(targets[0]["OnlyTestIdentifiers"] as? [String] == [
            "GenerateAcceptanceTestAppWithMacBundle",
            "GenerateAcceptanceTestSPMPackage",
        ])
    }

    @Test
    func filterXCTestRun_legacyFormat_suiteGranularity_keepsModuleAndSetsOnlyTestIdentifiers() throws {
        // Given
        let plistData = try makePlist([
            "__xctestrun_metadata__": ["FormatVersion": 1],
            "AppTests": ["BlueprintName": "AppTests"],
        ])

        // When
        let filtered = try subject.filterXCTestRun(
            plistData: plistData,
            modules: ["AppTests"],
            suites: ["AppTests": ["LoginTests", "SignupTests"]]
        )

        // Then
        let result = try parsePlist(filtered)
        let target = result["AppTests"] as! [String: Any]
        #expect(target["OnlyTestIdentifiers"] as? [String] == ["LoginTests", "SignupTests"])
    }

    // MARK: - Helpers

    private func makePlist(_ dict: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }

    private func parsePlist(_ data: Data) throws -> [String: Any] {
        try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    }

    private func blueprintNames(from plist: [String: Any]) -> [String] {
        let configurations = plist["TestConfigurations"] as? [[String: Any]] ?? []
        return configurations.flatMap { blueprintNames(fromConfig: $0) }
    }

    private func blueprintNames(fromConfig config: [String: Any]) -> [String] {
        let targets = config["TestTargets"] as? [[String: Any]] ?? []
        return targets.compactMap { $0["BlueprintName"] as? String }
    }
}
