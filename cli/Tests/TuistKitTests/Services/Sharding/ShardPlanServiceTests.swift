import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistAppleArchiver
import TuistServer

@testable import TuistKit

struct ShardPlanServiceTests {
    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func plan_withArchivePath_writesOptimizedArchiveAndSkipsRemoteUpload_evenWhenSkipUploadIsEnabled() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()

        let testProductsPath = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        try await fileSystem.makeDirectory(at: testProductsPath)
        try await fileSystem.writeText("payload", at: testProductsPath.appending(component: "file.txt"))
        try await fileSystem.writeAsPlist(
            XCTestRunFixture(
                testConfigurations: [
                    .init(
                        testTargets: [
                            .init(blueprintName: "AppTests"),
                        ]
                    ),
                ]
            ),
            at: testProductsPath.appending(component: "MyApp.xctestrun"),
            encoder: plistEncoder()
        )

        let dsymPath = testProductsPath.appending(components: "MyApp.framework.dSYM", "Contents", "Resources")
        try await fileSystem.makeDirectory(at: dsymPath)
        try await fileSystem.writeText("debug", at: dsymPath.appending(component: "DWARF"))

        let createShardPlanService = MockCreateShardPlanServicing()
        given(createShardPlanService)
            .createShardPlan(
                fullHandle: .any,
                serverURL: .any,
                reference: .any,
                modules: .any,
                testSuites: .any,
                shardMin: .any,
                shardMax: .any,
                shardTotal: .any,
                shardMaxDuration: .any,
                shardGranularity: .any,
                buildRunId: .any
            )
            .willReturn(
                Components.Schemas.ShardPlan(
                    id: "plan-id",
                    reference: "ref",
                    shard_count: 2,
                    shards: []
                )
            )

        let startShardUploadService = MockStartShardUploadServicing()
        let shardMatrixOutputService = MockShardMatrixOutputServicing()
        given(shardMatrixOutputService)
            .output(.any)
            .willReturn()

        let subject = ShardPlanService(
            createShardPlanService: createShardPlanService,
            startShardUploadService: startShardUploadService,
            fileSystem: fileSystem,
            shardMatrixOutputService: shardMatrixOutputService
        )

        let archivePath = temporaryDirectory.appending(components: "artifacts", "bundle.aar")

        _ = try await subject.plan(
            xctestproductsPath: testProductsPath,
            destination: nil,
            reference: "ref",
            shardGranularity: .module,
            shardMin: nil,
            shardMax: nil,
            shardTotal: 2,
            shardMaxDuration: nil,
            fullHandle: "tuist/tuist",
            serverURL: URL(string: "https://tuist.dev")!,
            buildRunId: nil,
            skipUpload: true,
            archivePath: archivePath
        )

        let archiveExists = try await fileSystem.exists(archivePath)
        #expect(archiveExists)

        let extractedPath = temporaryDirectory.appending(component: "extracted")
        try await fileSystem.makeDirectory(at: extractedPath)
        try await AppleArchiver().decompress(archive: archivePath, to: extractedPath)

        let payloadExists = try await fileSystem.exists(extractedPath.appending(component: "file.txt"))
        #expect(payloadExists)
        let extractedContent = try await fileSystem.readTextFile(at: extractedPath.appending(component: "file.txt"))
        #expect(extractedContent == "payload")

        let dsymExists = try await fileSystem.exists(extractedPath.appending(component: "MyApp.framework.dSYM"))
        #expect(!dsymExists)

        verify(startShardUploadService)
            .startUpload(fullHandle: .any, serverURL: .any, reference: .any)
            .called(0)
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

    enum CodingKeys: String, CodingKey {
        case blueprintName = "BlueprintName"
    }
}

private func plistEncoder() -> PropertyListEncoder {
    let encoder = PropertyListEncoder()
    encoder.outputFormat = .xml
    return encoder
}
