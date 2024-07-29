import FileSystem
import Mockable
import MockableTest
import TuistCore
import TuistServer
import TuistSupport
import XcodeGraph
import XCTest
@testable import TuistAnalytics
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistSupportTesting

final class TuistAnalyticsDispatcherTests: TuistUnitTestCase {
    private var subject: TuistAnalyticsDispatcher!
    private var createCommandEventService: MockCreateCommandEventServicing!
    private var ciChecker: MockCIChecking!
    private var cacheDirectoriesProviderFactory: MockCacheDirectoriesProviderFactoring!
    private var analyticsArtifactUploadService: MockAnalyticsArtifactUploadServicing!

    override func setUp() {
        super.setUp()
        createCommandEventService = .init()
        ciChecker = .init()
        cacheDirectoriesProviderFactory = .init()
        analyticsArtifactUploadService = .init()
    }

    override func tearDown() {
        subject = nil
        createCommandEventService = nil
        ciChecker = nil
        cacheDirectoriesProviderFactory = nil
        analyticsArtifactUploadService = nil
        super.tearDown()
    }

    func testDispatch_whenAnalyticsIsEnabled_sendsToServer() throws {
        // Given
        let fullHandle = "project"
        let url = URL.test()
        let backend = TuistAnalyticsServerBackend(
            fullHandle: fullHandle,
            url: url,
            createCommandEventService: createCommandEventService,
            fileHandler: fileHandler,
            ciChecker: ciChecker,
            cacheDirectoriesProviderFactory: cacheDirectoriesProviderFactory,
            analyticsArtifactUploadService: analyticsArtifactUploadService,
            fileSystem: FileSystem()
        )
        subject = TuistAnalyticsDispatcher(
            backend: backend
        )

        given(ciChecker)
            .isCI()
            .willReturn(false)
        given(createCommandEventService)
            .createCommandEvent(
                commandEvent: .matching { commandEvent in
                    commandEvent.name == Self.commandEvent.name
                },
                projectId: .value(fullHandle),
                serverURL: .value(url)
            )
            .willReturn(.test(id: 10))

        given(analyticsArtifactUploadService)
            .uploadResultBundle(
                .any,
                targetHashes: .any,
                graphPath: .any,
                commandEventId: .value(10),
                serverURL: .value(url)
            )
            .willReturn(())

        let cacheDirectoriesProvider = MockCacheDirectoriesProviding()

        given(cacheDirectoriesProviderFactory)
            .cacheDirectories()
            .willReturn(cacheDirectoriesProvider)

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(try temporaryPath())

        // When
        let expectation = XCTestExpectation(description: "completion is called")
        try subject.dispatch(event: Self.commandEvent, completion: { expectation.fulfill() })

        // Then
        _ = XCTWaiter.wait(for: [expectation], timeout: 1.0)
    }

    static var commandEvent: CommandEvent {
        CommandEvent(
            runId: "run-id",
            name: "event",
            subcommand: nil,
            params: [:],
            commandArguments: ["event"],
            durationInMs: 100,
            clientId: "client",
            tuistVersion: "2.0.0",
            swiftVersion: "5.5",
            macOSVersion: "12.0",
            machineHardwareName: "arm64",
            isCI: false,
            status: .success
        )
    }

    static func commandEventData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(Self.commandEvent)
    }
}
