import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistAppleArchiver
import TuistCI
import TuistLoggerTesting
import TuistLogging
import TuistServer
import TuistSupport
import TuistTesting

@testable import TuistKit

struct ShardServiceTests {
    // MARK: - testIdentifiers derivation

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func shard_moduleGranularity_emitsBareModuleOnlyTestingIdentifiers() async throws {
        // Given: a plan with no suites (module granularity)
        let (subject, testProductsPath) = try await makeSubjectWithLocalProducts(
            modules: ["CoreTests", "AppTests"],
            suites: [:]
        )

        // When
        let shard = try await subject.shard(
            shardIndex: 0,
            fullHandle: "org/project",
            serverURL: URL(string: "https://tuist.dev")!,
            reference: nil,
            testProductsPath: testProductsPath,
            testProductsArchivePath: nil
        )

        // Then: identifiers are bare, sorted module names
        #expect(shard.testIdentifiers == ["AppTests", "CoreTests"])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies(), .withMockedLogger())
    func shard_suiteGranularity_emitsModuleSlashSuiteOnlyTestingIdentifiers() async throws {
        // Given: a plan with suites grouped by module (suite granularity)
        let (subject, testProductsPath) = try await makeSubjectWithLocalProducts(
            modules: ["AppTests", "CoreTests"],
            suites: [
                "AppTests": ["SignupTests", "LoginTests"],
                "CoreTests": ["NetworkTests"],
            ]
        )

        // When
        let shard = try await subject.shard(
            shardIndex: 0,
            fullHandle: "org/project",
            serverURL: URL(string: "https://tuist.dev")!,
            reference: nil,
            testProductsPath: testProductsPath,
            testProductsArchivePath: nil
        )

        // Then: identifiers are `Module/Suite`, sorted and stable
        #expect(shard.testIdentifiers == [
            "AppTests/LoginTests",
            "AppTests/SignupTests",
            "CoreTests/NetworkTests",
        ])
        #expect(Logger.testingLogHandler
            .collected[.notice, ==] == "Shard 0: AppTests/LoginTests, AppTests/SignupTests, CoreTests/NetworkTests")
    }

    // MARK: - shard() with local test products path

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func shard_withLocalTestProductsPath_skipsDownloadAndDoesNotMutateXCTestRun() async throws {
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
                download_urls: [],
                modules: ["AppTests"],
                shard_plan_id: "plan-123",
                skip: [],
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
            reference: nil,
            testProductsPath: testProductsPath,
            testProductsArchivePath: nil
        )

        #expect(shard.testProductsPath == testProductsPath)
        #expect(shard.modules == ["AppTests"])
        #expect(shard.shardPlanId == "plan-123")

        // The bundle's xctestrun is left untouched; selection is delegated to `-only-testing`.
        let originalXCTestRunData = try await fileSystem.readFile(at: xctestrunPath)
        let originalPlist = try parsePlist(originalXCTestRunData)
        #expect(blueprintNames(from: originalPlist) == ["AppTests", "CoreTests"])
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies(), .withMockedLogger())
    func shard_catchAllShard_carriesSkipTestIdentifiersAndNoOnlyTesting() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let testProductsPath = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        try await fileSystem.makeDirectory(at: testProductsPath)

        let ciController = MockCIControlling()
        given(ciController).ciInfo().willReturn(.test(provider: .github))

        // The catch-all shard carries no modules/suites (no -only-testing) and a skip list of every suite
        // assigned to other shards, so it runs the remainder via -skip-testing.
        let getShardService = MockGetShardServicing()
        given(getShardService).getShard(
            fullHandle: .any,
            serverURL: .any,
            reference: .any,
            shardIndex: .any
        ).willReturn(
            Components.Schemas.Shard(
                download_url: "https://example.com/should-not-be-used",
                modules: [],
                shard_plan_id: "plan-123",
                skip: ["AppTests/LoginTests", "CoreTests/NetworkTests"],
                suites: .init()
            )
        )

        let subject = ShardService(
            getShardService: getShardService,
            ciController: ciController,
            fileSystem: fileSystem
        )

        let shard = try await subject.shard(
            shardIndex: 2,
            fullHandle: "org/project",
            serverURL: URL(string: "https://tuist.dev")!,
            reference: nil,
            testProductsPath: testProductsPath,
            testProductsArchivePath: nil
        )

        // No -only-testing; the remainder is selected by skipping everything already assigned.
        #expect(shard.testIdentifiers.isEmpty)
        #expect(shard.skipTestIdentifiers == ["AppTests/LoginTests", "CoreTests/NetworkTests"])
        #expect(Logger.testingLogHandler.collected[.notice, ==] == "Shard 2: AppTests/LoginTests, CoreTests/NetworkTests")
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func shard_explicitReference_isForwardedToGetShard() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let testProductsPath = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        try await fileSystem.makeDirectory(at: testProductsPath)
        try await fileSystem.writeAsPlist(
            XCTestRunFixture(
                testConfigurations: [
                    .init(testTargets: [.init(blueprintName: "AppTests", testHostPath: "/path/to/host")]),
                ]
            ),
            at: testProductsPath.appending(component: "MyApp.xctestrun"),
            encoder: plistEncoder()
        )

        let ciController = MockCIControlling()
        // Asserts that the explicit reference wins over the CI-derived one.
        given(ciController).ciInfo().willReturn(.test(provider: .circleci, runId: "ci-derived-ref"))

        let getShardService = MockGetShardServicing()
        given(getShardService).getShard(
            fullHandle: .any,
            serverURL: .any,
            reference: .value("explicit-ref"),
            shardIndex: .any
        ).willReturn(
            Components.Schemas.Shard(
                download_url: "https://example.com/unused",
                download_urls: [],
                modules: ["AppTests"],
                shard_plan_id: "plan-123",
                skip: [],
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
            reference: "explicit-ref",
            testProductsPath: testProductsPath,
            testProductsArchivePath: nil
        )

        #expect(shard.reference == "explicit-ref")
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
                download_urls: [],
                modules: ["AppTests"],
                shard_plan_id: "plan-123",
                skip: [],
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
                reference: nil,
                testProductsPath: testProductsPath,
                testProductsArchivePath: nil
            )
        }
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func shard_withLocalTestProductsArchivePath_extractsArchiveWithoutMutatingXCTestRun() async throws {
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
                download_urls: [],
                modules: ["AppTests"],
                shard_plan_id: "plan-123",
                skip: [],
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
            reference: nil,
            testProductsPath: nil,
            testProductsArchivePath: archivePath
        )

        #expect(shard.modules == ["AppTests"])
        #expect(shard.testProductsPath.basename.hasSuffix(".xctestproducts"))

        // The extracted xctestrun is preserved as-is (not filtered).
        let extractedXCTestRunPath = try #require(
            try await fileSystem
                .glob(directory: shard.testProductsPath, include: ["**/*.xctestrun"])
                .collect()
                .first
        )
        let extractedXCTestRunData = try await fileSystem.readFile(at: extractedXCTestRunPath)
        #expect(blueprintNames(from: try parsePlist(extractedXCTestRunData)) == ["AppTests", "CoreTests"])

        let extractedFilePath = shard.testProductsPath.appending(component: "file.txt")
        let extractedContent = try await fileSystem.readTextFile(at: extractedFilePath)
        #expect(extractedContent == "fixture")
    }

    // MARK: - Helpers

    private func makeSubjectWithLocalProducts(
        modules: [String],
        suites: [String: [String]]
    ) async throws -> (ShardService, AbsolutePath) {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let testProductsPath = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        try await fileSystem.makeDirectory(at: testProductsPath)
        try await fileSystem.writeAsPlist(
            XCTestRunFixture(
                testConfigurations: [
                    .init(testTargets: modules.map { .init(blueprintName: $0, testHostPath: "/path/to/\($0)") }),
                ]
            ),
            at: testProductsPath.appending(component: "MyApp.xctestrun"),
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
                download_url: "https://example.com/unused",
                modules: modules,
                shard_plan_id: "plan-123",
                skip: [],
                suites: .init(additionalProperties: suites)
            )
        )

        let subject = ShardService(
            getShardService: getShardService,
            ciController: ciController,
            fileSystem: fileSystem
        )
        return (subject, testProductsPath)
    }

    private func parsePlist(_ data: Data) throws -> [String: Any] {
        try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
    }

    private func blueprintNames(from plist: [String: Any]) -> [String] {
        let configurations = plist["TestConfigurations"] as? [[String: Any]] ?? []
        return configurations.flatMap { config in
            (config["TestTargets"] as? [[String: Any]] ?? []).compactMap { $0["BlueprintName"] as? String }
        }
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
