import FileSystem
import MockableTest
import TuistAnalytics
import TuistCore
import TuistCoreTesting
import TuistServer
import TuistSupport
import XcodeGraph
import XCTest
@testable import TuistKit
@testable import TuistSupportTesting

final class TuistAnalyticsServerBackendTests: TuistUnitTestCase {
    private var fullHandle = "tuist-org/tuist"
    private var createCommandEventService: MockCreateCommandEventServicing!
    private var ciChecker: MockCIChecking!
    private var cacheDirectoriesProviderFactory: MockCacheDirectoriesProviderFactoring!
    private var analyticsArtifactUploadService: MockAnalyticsArtifactUploadServicing!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var subject: TuistAnalyticsServerBackend!

    override func setUpWithError() throws {
        super.setUp()
        createCommandEventService = .init()
        ciChecker = .init()
        cacheDirectoriesProviderFactory = .init()
        analyticsArtifactUploadService = .init()
        cacheDirectoriesProvider = .init()
        given(cacheDirectoriesProviderFactory)
            .cacheDirectories()
            .willReturn(cacheDirectoriesProvider)
        subject = TuistAnalyticsServerBackend(
            fullHandle: fullHandle,
            url: Constants.URLs.production,
            createCommandEventService: createCommandEventService,
            fileHandler: fileHandler,
            ciChecker: ciChecker,
            cacheDirectoriesProviderFactory: cacheDirectoriesProviderFactory,
            analyticsArtifactUploadService: analyticsArtifactUploadService,
            fileSystem: FileSystem()
        )
    }

    override func tearDown() {
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
            .cacheDirectory(for: .value(.runs))
            .willReturn(try temporaryPath())
        given(ciChecker)
            .isCI()
            .willReturn(false)
        let event = CommandEvent.test()
        given(createCommandEventService)
            .createCommandEvent(
                commandEvent: .value(event),
                projectId: .value(fullHandle),
                serverURL: .value(Constants.URLs.production)
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
            .cacheDirectory(for: .value(.runs))
            .willReturn(try temporaryPath())
        given(ciChecker)
            .isCI()
            .willReturn(true)
        let event = CommandEvent.test()
        given(createCommandEventService)
            .createCommandEvent(
                commandEvent: .value(event),
                projectId: .value(fullHandle),
                serverURL: .value(Constants.URLs.production)
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
        given(ciChecker)
            .isCI()
            .willReturn(true)
        let event = CommandEvent.test()
        given(createCommandEventService)
            .createCommandEvent(
                commandEvent: .value(event),
                projectId: .value(fullHandle),
                serverURL: .value(Constants.URLs.production)
            )
            .willReturn(
                .test(
                    id: 10,
                    url: URL(string: "https://cloud.tuist.io/tuist-org/tuist/runs/10")!
                )
            )

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(try temporaryPath())

        let resultBundle = try cacheDirectoriesProvider
            .cacheDirectory(for: .runs)
            .appending(components: event.runId, "\(Constants.resultBundleName).xcresult")
        try fileHandler.createFolder(resultBundle)

        given(analyticsArtifactUploadService)
            .uploadResultBundle(
                .value(resultBundle),
                targetHashes: .any,
                graphPath: .any,
                commandEventId: .value(10),
                serverURL: .value(Constants.URLs.production)
            )
            .willReturn(())

        // When
        try await subject.send(commandEvent: event)

        // Then
        XCTAssertStandardOutput(pattern: "You can view a detailed report at: https://cloud.tuist.io/tuist-org/tuist/runs/10")
        XCTAssertFalse(fileHandler.exists(resultBundle))
    }
}
