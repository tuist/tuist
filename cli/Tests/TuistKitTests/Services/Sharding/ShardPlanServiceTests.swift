import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Path
import Testing
import TuistAppleArchiver
import TuistAutomation
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
                    shards: [],
                    upload_url: "https://tuist.dev/api/projects/tuist/tuist/tests/shards/upload/start"
                )
            )

        let shardMatrixOutputService = MockShardMatrixOutputServicing()
        given(shardMatrixOutputService)
            .output(.any)
            .willReturn()

        let subject = ShardPlanService(
            createShardPlanService: createShardPlanService,
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
            serverURL: try #require(URL(string: "https://tuist.dev")),
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
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func plan_withRemoteUpload_usesUploadStartedWithShardPlan() async throws {
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
                    shards: [],
                    upload_url: "https://tuist.dev/api/projects/tuist/tuist/tests/shards/upload/start"
                )
            )

        let startShardUploadService = MockStartShardUploadServicing()
        given(startShardUploadService)
            .startUpload(
                fullHandle: .any,
                serverURL: .any,
                shardPlanId: .value("plan-id")
            )
            .willReturn("upload-id")

        let multipartUploadArtifactService = MockMultipartUploadArtifactServicing()
        var generateUploadURLCallback: ((MultipartUploadArtifactPart) async throws -> String)?
        given(multipartUploadArtifactService)
            .multipartUploadArtifact(
                artifactPath: .matching { $0.extension == "aar" },
                generateUploadURL: .matching { callback in
                    generateUploadURLCallback = callback
                    return true
                },
                updateProgress: .any
            )
            .willReturn([(etag: "etag", partNumber: 1)])

        let multipartUploadGenerateURLShardsService = MockMultipartUploadGenerateURLShardsServicing()
        given(multipartUploadGenerateURLShardsService)
            .generateUploadURL(
                fullHandle: .any,
                serverURL: .any,
                shardPlanId: .value("plan-id"),
                reference: .any,
                uploadId: .value("upload-id"),
                partNumber: .value(1)
            )
            .willReturn("https://tuist.dev/upload")

        let multipartUploadCompleteShardsService = MockMultipartUploadCompleteShardsServicing()
        given(multipartUploadCompleteShardsService)
            .completeUpload(
                fullHandle: .any,
                serverURL: .any,
                shardPlanId: .value("plan-id"),
                reference: .any,
                uploadId: .value("upload-id"),
                parts: .matching { parts in
                    parts.count == 1 && parts[0].partNumber == 1 && parts[0].etag == "etag"
                }
            )
            .willReturn()

        let shardMatrixOutputService = MockShardMatrixOutputServicing()
        given(shardMatrixOutputService)
            .output(.any)
            .willReturn()

        let subject = ShardPlanService(
            createShardPlanService: createShardPlanService,
            startShardUploadService: startShardUploadService,
            multipartUploadArtifactService: multipartUploadArtifactService,
            multipartUploadGenerateURLShardsService: multipartUploadGenerateURLShardsService,
            multipartUploadCompleteShardsService: multipartUploadCompleteShardsService,
            fileSystem: fileSystem,
            shardMatrixOutputService: shardMatrixOutputService
        )

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
            serverURL: try #require(URL(string: "https://tuist.dev")),
            buildRunId: nil,
            skipUpload: false,
            archivePath: nil
        )

        let callback = try #require(generateUploadURLCallback)
        let uploadURL = try await callback(
            MultipartUploadArtifactPart(
                number: 1,
                contentLength: 20
            )
        )
        #expect(uploadURL == "https://tuist.dev/upload")
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func plan_suiteGranularity_retriesEnumeration_untilAllXCTestRunModulesAreCovered() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let testProductsPath = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        try await writeXCTestProducts(modules: ["AppTests", "FeatureTests"], at: testProductsPath, fileSystem: fileSystem)

        // Enumeration is flaky: the first attempt only discovers AppTests, the retry discovers both modules.
        let xcTestEnumerator = MockXCTestEnumerating()
        let callCounter = CallCounter()
        given(xcTestEnumerator)
            .enumerateTests(testProductsPath: .any, destination: .any)
            .willProduce { _, _ in
                if callCounter.next() == 1 {
                    return [XCTestRun.TestTarget(blueprintName: "AppTests", onlyTestIdentifiers: ["LoginTests"])]
                }
                return [
                    XCTestRun.TestTarget(blueprintName: "AppTests", onlyTestIdentifiers: ["LoginTests"]),
                    XCTestRun.TestTarget(blueprintName: "FeatureTests", onlyTestIdentifiers: ["FeatureFlagTests"]),
                ]
            }

        var capturedTestSuites: [String]?
        let createShardPlanService = mockCreateShardPlanService(capturingTestSuites: { capturedTestSuites = $0 })
        let shardMatrixOutputService = MockShardMatrixOutputServicing()
        given(shardMatrixOutputService).output(.any).willReturn()

        let subject = ShardPlanService(
            xcTestEnumerator: xcTestEnumerator,
            createShardPlanService: createShardPlanService,
            fileSystem: fileSystem,
            shardMatrixOutputService: shardMatrixOutputService
        )

        _ = try await subject.plan(
            xctestproductsPath: testProductsPath,
            destination: "platform=macOS",
            reference: "ref",
            shardGranularity: .suite,
            shardMin: nil,
            shardMax: nil,
            shardTotal: 1,
            shardMaxDuration: nil,
            fullHandle: "tuist/tuist",
            serverURL: try #require(URL(string: "https://tuist.dev")),
            buildRunId: nil,
            skipUpload: true,
            archivePath: nil
        )

        // The dropped FeatureTests module is recovered by the retry rather than silently omitted.
        #expect(capturedTestSuites?.sorted() == ["AppTests/LoginTests", "FeatureTests/FeatureFlagTests"])
        verify(xcTestEnumerator).enumerateTests(testProductsPath: .any, destination: .any).called(2)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func plan_suiteGranularity_buildsSuitesForEveryModule_inASingleAttempt() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let testProductsPath = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        try await writeXCTestProducts(modules: ["AppTests", "FeatureTests"], at: testProductsPath, fileSystem: fileSystem)

        let xcTestEnumerator = MockXCTestEnumerating()
        given(xcTestEnumerator)
            .enumerateTests(testProductsPath: .any, destination: .any)
            .willReturn([
                XCTestRun.TestTarget(blueprintName: "AppTests", onlyTestIdentifiers: ["LoginTests", "SignupTests"]),
                XCTestRun.TestTarget(blueprintName: "FeatureTests", onlyTestIdentifiers: ["FeatureFlagTests"]),
            ])

        var capturedTestSuites: [String]?
        let createShardPlanService = mockCreateShardPlanService(capturingTestSuites: { capturedTestSuites = $0 })
        let shardMatrixOutputService = MockShardMatrixOutputServicing()
        given(shardMatrixOutputService).output(.any).willReturn()

        let subject = ShardPlanService(
            xcTestEnumerator: xcTestEnumerator,
            createShardPlanService: createShardPlanService,
            fileSystem: fileSystem,
            shardMatrixOutputService: shardMatrixOutputService
        )

        _ = try await subject.plan(
            xctestproductsPath: testProductsPath,
            destination: "platform=macOS",
            reference: "ref",
            shardGranularity: .suite,
            shardMin: nil,
            shardMax: nil,
            shardTotal: 1,
            shardMaxDuration: nil,
            fullHandle: "tuist/tuist",
            serverURL: try #require(URL(string: "https://tuist.dev")),
            buildRunId: nil,
            skipUpload: true,
            archivePath: nil
        )

        #expect(
            capturedTestSuites?.sorted() == ["AppTests/LoginTests", "AppTests/SignupTests", "FeatureTests/FeatureFlagTests"]
        )
        // A complete enumeration must not pay the cost of extra retries.
        verify(xcTestEnumerator).enumerateTests(testProductsPath: .any, destination: .any).called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func plan_suiteGranularity_excludesModulesThatNeverEnumerate_withoutDroppingTheRest() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let testProductsPath = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        try await writeXCTestProducts(modules: ["AppTests", "EmptyTests"], at: testProductsPath, fileSystem: fileSystem)

        // EmptyTests never enumerates a test (e.g. a test target with no tests); AppTests always does.
        let xcTestEnumerator = MockXCTestEnumerating()
        given(xcTestEnumerator)
            .enumerateTests(testProductsPath: .any, destination: .any)
            .willReturn([XCTestRun.TestTarget(blueprintName: "AppTests", onlyTestIdentifiers: ["LoginTests"])])

        var capturedTestSuites: [String]?
        let createShardPlanService = mockCreateShardPlanService(capturingTestSuites: { capturedTestSuites = $0 })
        let shardMatrixOutputService = MockShardMatrixOutputServicing()
        given(shardMatrixOutputService).output(.any).willReturn()

        let subject = ShardPlanService(
            xcTestEnumerator: xcTestEnumerator,
            createShardPlanService: createShardPlanService,
            fileSystem: fileSystem,
            shardMatrixOutputService: shardMatrixOutputService
        )

        _ = try await subject.plan(
            xctestproductsPath: testProductsPath,
            destination: "platform=macOS",
            reference: "ref",
            shardGranularity: .suite,
            shardMin: nil,
            shardMax: nil,
            shardTotal: 1,
            shardMaxDuration: nil,
            fullHandle: "tuist/tuist",
            serverURL: try #require(URL(string: "https://tuist.dev")),
            buildRunId: nil,
            skipUpload: true,
            archivePath: nil
        )

        // The plan is still created with the suites that did enumerate (no crash, no empty plan).
        #expect(capturedTestSuites == ["AppTests/LoginTests"])
        // It retries once on the shortfall, then stops when no new module is discovered.
        verify(xcTestEnumerator).enumerateTests(testProductsPath: .any, destination: .any).called(2)
    }

    private func mockCreateShardPlanService(
        capturingTestSuites capture: @escaping ([String]?) -> Void
    ) -> MockCreateShardPlanServicing {
        let createShardPlanService = MockCreateShardPlanServicing()
        given(createShardPlanService)
            .createShardPlan(
                fullHandle: .any,
                serverURL: .any,
                reference: .any,
                modules: .any,
                testSuites: .matching { capture($0); return true },
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
                    shard_count: 1,
                    shards: [],
                    upload_url: "https://tuist.dev/api/projects/tuist/tuist/tests/shards/upload/start"
                )
            )
        return createShardPlanService
    }

    private func writeXCTestProducts(modules: [String], at testProductsPath: AbsolutePath, fileSystem: FileSystem) async throws {
        try await fileSystem.makeDirectory(at: testProductsPath)
        try await fileSystem.writeAsPlist(
            XCTestRunFixture(
                testConfigurations: [
                    .init(testTargets: modules.map { TestTargetFixture(blueprintName: $0) }),
                ]
            ),
            at: testProductsPath.appending(component: "MyApp.xctestrun"),
            encoder: plistEncoder()
        )
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
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
