import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistAppleArchiver
import TuistCI
import TuistServer
import TuistSupport
import TuistTesting

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

    // MARK: - shard() with local test products path

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func shard_withLocalTestProductsPath_skipsDownloadAndWritesFilteredXCTestRun() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let testProductsPath = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        try await fileSystem.makeDirectory(at: testProductsPath)

        let xctestrunPath = testProductsPath.appending(component: "MyApp.xctestrun")
        try await fileSystem.writeAsPlist(
            XCTestRunFixture(
                testConfigurations: [
                    .init(
                        testTargets: [
                            .init(blueprintName: "AppTests", testHostPath: "/path/to/host"),
                            .init(blueprintName: "CoreTests", testHostPath: "/path/to/core"),
                        ]
                    ),
                ]
            ),
            at: xctestrunPath,
            encoder: plistEncoder()
        )

        let ciController = MockCIControlling()
        given(ciController).ciInfo().willReturn(.test(provider: .github))

        let getShardService = MockGetShardServicing()
        given(getShardService).getShard(
            fullHandle: .any,
            serverURL: .any,
            reference: .any,
            shardIndex: .any
        ).willReturn(
            Components.Schemas.Shard(
                download_url: "https://example.com/should-not-be-used",
                modules: ["AppTests"],
                shard_plan_id: "plan-123",
                suites: .init()
            )
        )

        let subject = ShardService(
            getShardService: getShardService,
            ciController: ciController,
            fileSystem: fileSystem
        )

        let shard = try await subject.shard(
            shardIndex: 0,
            fullHandle: "org/project",
            serverURL: URL(string: "https://tuist.dev")!,
            testProductsPath: testProductsPath,
            testProductsArchivePath: nil
        )

        #expect(shard.testProductsPath == testProductsPath)
        #expect(shard.xcTestRunPath != nil)
        #expect(shard.modules == ["AppTests"])
        #expect(shard.shardPlanId == "plan-123")

        let filteredXCTestRunData = try await fileSystem.readFile(at: shard.xcTestRunPath!)
        let filteredPlist = try parsePlist(filteredXCTestRunData)
        let targets = blueprintNames(from: filteredPlist)
        #expect(targets == ["AppTests"])

        let originalXCTestRunData = try await fileSystem.readFile(at: xctestrunPath)
        let originalPlist = try parsePlist(originalXCTestRunData)
        let originalTargets = blueprintNames(from: originalPlist)
        #expect(originalTargets == ["AppTests", "CoreTests"])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func shard_withLocalTestProductsPath_throwsWhenNoXCTestRunFound() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let testProductsPath = temporaryDirectory.appending(component: "Empty.xctestproducts")
        try await fileSystem.makeDirectory(at: testProductsPath)

        let ciController = MockCIControlling()
        given(ciController).ciInfo().willReturn(.test(provider: .github))

        let getShardService = MockGetShardServicing()
        given(getShardService).getShard(
            fullHandle: .any,
            serverURL: .any,
            reference: .any,
            shardIndex: .any
        ).willReturn(
            Components.Schemas.Shard(
                download_url: "https://example.com/unused",
                modules: ["AppTests"],
                shard_plan_id: "plan-123",
                suites: .init()
            )
        )

        let subject = ShardService(
            getShardService: getShardService,
            ciController: ciController,
            fileSystem: fileSystem
        )

        await #expect(throws: ShardServiceError.xcTestRunNotFound(testProductsPath)) {
            try await subject.shard(
                shardIndex: 0,
                fullHandle: "org/project",
                serverURL: URL(string: "https://tuist.dev")!,
                testProductsPath: testProductsPath,
                testProductsArchivePath: nil
            )
        }
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func shard_withLocalTestProductsArchivePath_extractsArchiveAndFiltersXCTestRunInPlace() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let sourceProductsPath = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        try await fileSystem.makeDirectory(at: sourceProductsPath)

        let originalXCTestRunPath = sourceProductsPath.appending(component: "MyApp.xctestrun")
        try await fileSystem.writeAsPlist(
            XCTestRunFixture(
                testConfigurations: [
                    .init(
                        testTargets: [
                            .init(blueprintName: "AppTests", testHostPath: "/path/to/host"),
                            .init(blueprintName: "CoreTests", testHostPath: "/path/to/core"),
                        ]
                    ),
                ]
            ),
            at: originalXCTestRunPath,
            encoder: plistEncoder()
        )
        try await fileSystem.writeText("fixture", at: sourceProductsPath.appending(component: "file.txt"))

        let archivePath = temporaryDirectory.appending(component: "bundle.aar")
        try await AppleArchiver().compress(
            directory: sourceProductsPath,
            to: archivePath,
            excludePatterns: []
        )

        let ciController = MockCIControlling()
        given(ciController).ciInfo().willReturn(.test(provider: .github))

        let getShardService = MockGetShardServicing()
        given(getShardService).getShard(
            fullHandle: .any,
            serverURL: .any,
            reference: .any,
            shardIndex: .any
        ).willReturn(
            Components.Schemas.Shard(
                download_url: "https://example.com/unused",
                modules: ["AppTests"],
                shard_plan_id: "plan-123",
                suites: .init()
            )
        )

        let subject = ShardService(
            getShardService: getShardService,
            ciController: ciController,
            fileSystem: fileSystem
        )

        let shard = try await subject.shard(
            shardIndex: 0,
            fullHandle: "org/project",
            serverURL: URL(string: "https://tuist.dev")!,
            testProductsPath: nil,
            testProductsArchivePath: archivePath
        )

        #expect(shard.xcTestRunPath == nil)
        #expect(shard.modules == ["AppTests"])

        let extractedXCTestRunPath = try #require(
            try await fileSystem
                .glob(directory: shard.testProductsPath, include: ["**/*.xctestrun"])
                .collect()
                .first
        )
        let filteredXCTestRunData = try await fileSystem.readFile(at: extractedXCTestRunPath)
        let filteredPlist = try parsePlist(filteredXCTestRunData)
        #expect(blueprintNames(from: filteredPlist) == ["AppTests"])

        let extractedFilePath = shard.testProductsPath.appending(component: "file.txt")
        let extractedContent = try await fileSystem.readTextFile(at: extractedFilePath)
        #expect(extractedContent == "fixture")
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

private struct XCTestRunFixture: Encodable {
    let testConfigurations: [TestConfigurationFixture]

    enum CodingKeys: String, CodingKey {
        case testConfigurations = "TestConfigurations"
    }
}

private struct TestConfigurationFixture: Encodable {
    let testTargets: [TestTargetFixture]

    enum CodingKeys: String, CodingKey {
        case testTargets = "TestTargets"
    }
}

private struct TestTargetFixture: Encodable {
    let blueprintName: String
    let testHostPath: String?

    enum CodingKeys: String, CodingKey {
        case blueprintName = "BlueprintName"
        case testHostPath = "TestHostPath"
    }
}

private func plistEncoder() -> PropertyListEncoder {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .xml
    return encoder
}
