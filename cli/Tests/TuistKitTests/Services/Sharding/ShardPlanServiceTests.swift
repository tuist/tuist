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
    func plan_suiteGranularity_recoversModulesDroppedByTheBulkPass() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let testProductsPath = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        try await writeXCTestProducts(modules: ["AppTests", "FeatureTests"], at: testProductsPath, fileSystem: fileSystem)

        // The bulk pass (no -only-testing) only reports AppTests; the per-target recovery for the missing
        // FeatureTests (run with -only-testing FeatureTests) recovers it rather than silently dropping it.
        let xcTestEnumerator = MockXCTestEnumerating()
        given(xcTestEnumerator)
            .enumerateTests(testProductsPath: .any, destination: .any, onlyTesting: .any)
            .willProduce { _, _, onlyTesting in
                if onlyTesting.isEmpty {
                    return XCTestEnumeration(targets: [
                        XCTestRun.TestTarget(blueprintName: "AppTests", onlyTestIdentifiers: ["LoginTests"]),
                    ])
                }
                return XCTestEnumeration(targets: [
                    XCTestRun.TestTarget(blueprintName: "FeatureTests", onlyTestIdentifiers: ["FeatureFlagTests"]),
                ])
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

        // The dropped FeatureTests module is recovered by the per-target pass rather than silently omitted.
        #expect(capturedTestSuites?.sorted() == ["AppTests/LoginTests", "FeatureTests/FeatureFlagTests"])
        // One bulk pass plus one targeted recovery pass for the dropped module.
        verify(xcTestEnumerator).enumerateTests(testProductsPath: .any, destination: .any, onlyTesting: .any).called(2)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func plan_suiteGranularity_buildsSuitesForEveryModule_inASingleBulkPass() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let testProductsPath = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        try await writeXCTestProducts(modules: ["AppTests", "FeatureTests"], at: testProductsPath, fileSystem: fileSystem)

        let xcTestEnumerator = MockXCTestEnumerating()
        given(xcTestEnumerator)
            .enumerateTests(testProductsPath: .any, destination: .any, onlyTesting: .any)
            .willReturn(XCTestEnumeration(targets: [
                XCTestRun.TestTarget(blueprintName: "AppTests", onlyTestIdentifiers: ["LoginTests", "SignupTests"]),
                XCTestRun.TestTarget(blueprintName: "FeatureTests", onlyTestIdentifiers: ["FeatureFlagTests"]),
            ]))

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
        // A complete bulk pass needs no per-target recovery.
        verify(xcTestEnumerator).enumerateTests(testProductsPath: .any, destination: .any, onlyTesting: .any).called(1)
    }

    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func plan_suiteGranularity_excludesModulesThatEnumerateNoTests() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let testProductsPath = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        try await writeXCTestProducts(modules: ["AppTests", "EmptyTests"], at: testProductsPath, fileSystem: fileSystem)

        // EmptyTests enumerates but reports no tests (an empty target) with no errors; AppTests reports a
        // suite. Because a present-but-empty target is ambiguous, EmptyTests is re-enumerated in isolation,
        // which confirms (no errors) that it is genuinely empty.
        let xcTestEnumerator = MockXCTestEnumerating()
        given(xcTestEnumerator)
            .enumerateTests(testProductsPath: .any, destination: .any, onlyTesting: .any)
            .willReturn(XCTestEnumeration(targets: [
                XCTestRun.TestTarget(blueprintName: "AppTests", onlyTestIdentifiers: ["LoginTests"]),
                XCTestRun.TestTarget(blueprintName: "EmptyTests", onlyTestIdentifiers: []),
            ]))

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

        // EmptyTests enumerated no tests, so it is excluded; AppTests is unaffected.
        #expect(capturedTestSuites == ["AppTests/LoginTests"])
        // One bulk pass plus one isolated pass that confirms EmptyTests is genuinely empty (no errors).
        verify(xcTestEnumerator).enumerateTests(testProductsPath: .any, destination: .any, onlyTesting: .any).called(2)
    }

    /// A module that never enumerates — even after per-target recovery — must not be silently dropped: it is a
    /// genuine failure (e.g. a target that won't load) and fails plan creation loudly.
    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func plan_suiteGranularity_throwsForModulesThatNeverEnumerate() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let testProductsPath = temporaryDirectory.appending(component: "Backstop.xctestproducts")
        try await writeXCTestProducts(modules: ["AppTests", "GoneTests"], at: testProductsPath, fileSystem: fileSystem)

        // GoneTests never appears in any enumeration — bulk or per-target recovery — while AppTests does.
        let xcTestEnumerator = MockXCTestEnumerating()
        given(xcTestEnumerator)
            .enumerateTests(testProductsPath: .any, destination: .any, onlyTesting: .any)
            .willReturn(XCTestEnumeration(targets: [
                XCTestRun.TestTarget(blueprintName: "AppTests", onlyTestIdentifiers: ["LoginTests"]),
            ]))

        let createShardPlanService = mockCreateShardPlanService(capturingTestSuites: { _ in })
        let shardMatrixOutputService = MockShardMatrixOutputServicing()
        given(shardMatrixOutputService).output(.any).willReturn()

        let subject = ShardPlanService(
            xcTestEnumerator: xcTestEnumerator,
            createShardPlanService: createShardPlanService,
            fileSystem: fileSystem,
            shardMatrixOutputService: shardMatrixOutputService
        )

        let serverURL = try #require(URL(string: "https://tuist.dev"))
        await #expect(throws: ShardPlanServiceError.modulesFailedToEnumerate(["GoneTests"])) {
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
                serverURL: serverURL,
                buildRunId: nil,
                skipUpload: true,
                archivePath: nil
            )
        }

        // Bulk pass plus the bounded per-target recovery attempts before failing.
        verify(xcTestEnumerator)
            .enumerateTests(testProductsPath: .any, destination: .any, onlyTesting: .any).called(3)
    }

    /// A module the bulk pass reports present-but-empty *with* an accompanying enumeration error (e.g. a
    /// target that failed to boot) is ambiguous, so it is re-enumerated in isolation. When the isolated pass
    /// succeeds the module is recovered into the plan rather than silently dropped — the trade-me flaky-boot
    /// scenario where a re-boot discovers the tests the bulk pass missed.
    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func plan_suiteGranularity_recoversModuleReportedEmptyWithErrorsThatThenEnumerates() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let testProductsPath = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        try await writeXCTestProducts(modules: ["AppTests", "UITests"], at: testProductsPath, fileSystem: fileSystem)

        let xcTestEnumerator = MockXCTestEnumerating()
        given(xcTestEnumerator)
            .enumerateTests(testProductsPath: .any, destination: .any, onlyTesting: .any)
            .willProduce { _, _, onlyTesting in
                if onlyTesting.isEmpty {
                    // Bulk pass: UITests failed to boot — present but empty, with an error.
                    return XCTestEnumeration(
                        targets: [
                            XCTestRun.TestTarget(blueprintName: "AppTests", onlyTestIdentifiers: ["LoginTests"]),
                            XCTestRun.TestTarget(blueprintName: "UITests", onlyTestIdentifiers: []),
                        ],
                        errors: ["Cannot test target UITests: simulator failed to boot."]
                    )
                }
                // Isolated recovery pass: UITests boots and enumerates this time.
                return XCTestEnumeration(targets: [
                    XCTestRun.TestTarget(blueprintName: "UITests", onlyTestIdentifiers: ["SnapshotTests"]),
                ])
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

        // UITests is recovered by the isolated pass rather than silently dropped as "empty".
        #expect(capturedTestSuites?.sorted() == ["AppTests/LoginTests", "UITests/SnapshotTests"])
    }

    /// A module reported present-but-empty *with* an enumeration error on every pass (bulk and every isolated
    /// recovery attempt) failed to enumerate — a boot failure looks like a genuinely empty target except for
    /// the error. It must fail the plan loudly rather than being silently dropped, which is exactly the
    /// trade-me regression (a 70-target plan shipping only the dozen that happened to boot).
    @Test(.inTemporaryDirectory, .withMockedDependencies())
    func plan_suiteGranularity_throwsForModuleThatAlwaysEnumeratesEmptyWithErrors() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let testProductsPath = temporaryDirectory.appending(component: "MyApp.xctestproducts")
        try await writeXCTestProducts(modules: ["AppTests", "UITests"], at: testProductsPath, fileSystem: fileSystem)

        let xcTestEnumerator = MockXCTestEnumerating()
        given(xcTestEnumerator)
            .enumerateTests(testProductsPath: .any, destination: .any, onlyTesting: .any)
            .willReturn(XCTestEnumeration(
                targets: [
                    XCTestRun.TestTarget(blueprintName: "AppTests", onlyTestIdentifiers: ["LoginTests"]),
                    XCTestRun.TestTarget(blueprintName: "UITests", onlyTestIdentifiers: []),
                ],
                errors: ["Cannot test target UITests: simulator failed to boot."]
            ))

        let createShardPlanService = mockCreateShardPlanService(capturingTestSuites: { _ in })
        let shardMatrixOutputService = MockShardMatrixOutputServicing()
        given(shardMatrixOutputService).output(.any).willReturn()

        let subject = ShardPlanService(
            xcTestEnumerator: xcTestEnumerator,
            createShardPlanService: createShardPlanService,
            fileSystem: fileSystem,
            shardMatrixOutputService: shardMatrixOutputService
        )

        let serverURL = try #require(URL(string: "https://tuist.dev"))
        await #expect(throws: ShardPlanServiceError.modulesFailedToEnumerate(["UITests"])) {
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
                serverURL: serverURL,
                buildRunId: nil,
                skipUpload: true,
                archivePath: nil
            )
        }
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
