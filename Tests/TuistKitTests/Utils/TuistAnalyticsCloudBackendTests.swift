import MockableTest
import TuistAnalytics
import TuistCore
import TuistCoreTesting
import XcodeProjectGenerator
import TuistServer
import TuistSupport
import XCTest
@testable import TuistKit
@testable import TuistSupportTesting

final class TuistAnalyticsCloudBackendTests: TuistUnitTestCase {
    private var config: Cloud!
    private var createCommandEventService: MockCreateCommandEventServicing!
    private var ciChecker: MockCIChecker!
    private var cacheDirectoriesProviderFactory: MockCacheDirectoriesProviderFactoring!
    private var analyticsArtifactUploadService: MockAnalyticsArtifactUploadServicing!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var subject: TuistAnalyticsCloudBackend!

    override func setUpWithError() throws {
        super.setUp()
        config = Cloud.test(
            url: URL(string: "https://cloud.tuist.io")!,
            projectId: "tuist-org/tuist"
        )
        createCommandEventService = .init()
        ciChecker = .init()
        cacheDirectoriesProviderFactory = .init()
        analyticsArtifactUploadService = .init()
        cacheDirectoriesProvider = .init()
        given(cacheDirectoriesProviderFactory)
            .cacheDirectories()
            .willReturn(cacheDirectoriesProvider)
        subject = TuistAnalyticsCloudBackend(
            config: config,
            createCommandEventService: createCommandEventService,
            fileHandler: fileHandler,
            ciChecker: ciChecker,
            cacheDirectoriesProviderFactory: cacheDirectoriesProviderFactory,
            analyticsArtifactUploadService: analyticsArtifactUploadService
        )
    }

    override func tearDown() {
        config = nil
        createCommandEventService = nil
        ciChecker = nil
        cacheDirectoriesProviderFactory = nil
        analyticsArtifactUploadService = nil
        subject = nil
        super.tearDown()
    }

    func test_send_when_is_not_ci() async throws {
        // Given
        given(cacheDirectoriesProvider)
            .tuistCacheDirectory(for: .value(.runs))
            .willReturn(try temporaryPath())
        ciChecker.isCIStub = false
        let event = CommandEvent.test()
        given(createCommandEventService)
            .createCommandEvent(
                commandEvent: .value(event),
                projectId: .value(config.projectId),
                serverURL: .value(config.url)
            )
            .willReturn(
                .test(
                    id: 10,
                    url: URL(string: "https://cloud.tuist.io/tuist-org/tuist/runs/10")!
                )
            )

        // When
        try await subject.send(commandEvent: event)

        // Then
        XCTAssertPrinterOutputNotContains("You can view a detailed report at: https://cloud.tuist.io/tuist-org/tuist/runs/10")
    }

    func test_send_when_is_ci() async throws {
        // Given
        given(cacheDirectoriesProvider)
            .tuistCacheDirectory(for: .value(.runs))
            .willReturn(try temporaryPath())
        ciChecker.isCIStub = true
        let event = CommandEvent.test()
        given(createCommandEventService)
            .createCommandEvent(
                commandEvent: .value(event),
                projectId: .value(config.projectId),
                serverURL: .value(config.url)
            )
            .willReturn(
                .test(
                    id: 10,
                    url: URL(string: "https://cloud.tuist.io/tuist-org/tuist/runs/10")!
                )
            )

        // When
        try await subject.send(commandEvent: event)

        // Then
        XCTAssertStandardOutput(pattern: "You can view a detailed report at: https://cloud.tuist.io/tuist-org/tuist/runs/10")
    }

    func test_send_when_is_ci_and_result_bundle_exists() async throws {
        // Given
        ciChecker.isCIStub = true
        let event = CommandEvent.test()
        given(createCommandEventService)
            .createCommandEvent(
                commandEvent: .value(event),
                projectId: .value(config.projectId),
                serverURL: .value(config.url)
            )
            .willReturn(
                .test(
                    id: 10,
                    url: URL(string: "https://cloud.tuist.io/tuist-org/tuist/runs/10")!
                )
            )

        given(cacheDirectoriesProvider)
            .tuistCacheDirectory(for: .value(.runs))
            .willReturn(try temporaryPath())

        let resultBundle = try cacheDirectoriesProvider
            .tuistCacheDirectory(for: .runs)
            .appending(components: event.runId, "\(Constants.resultBundleName).xcresult")
        try fileHandler.createFolder(resultBundle)

        given(analyticsArtifactUploadService)
            .uploadAnalyticsArtifact(
                artifactPath: .value(resultBundle),
                commandEventId: .value(10),
                serverURL: .value(config.url)
            )
            .willReturn(())

        // When
        try await subject.send(commandEvent: event)

        // Then
        XCTAssertStandardOutput(pattern: "You can view a detailed report at: https://cloud.tuist.io/tuist-org/tuist/runs/10")
        XCTAssertFalse(fileHandler.exists(resultBundle))
    }
}
