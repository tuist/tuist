import FileSystem
import FileSystemTesting
import Foundation
import Mockable
import Testing
import TuistCore
import TuistServer
import TuistSupport
@testable import TuistAnalytics
@testable import TuistCoreTesting
@testable import TuistKit
@testable import TuistSupportTesting

struct TuistAnalyticsDispatcherTests {
    private var subject: TuistAnalyticsDispatcher!
    private var createCommandEventService: MockCreateCommandEventServicing!
    private var cacheDirectoriesProvider: MockCacheDirectoriesProviding!
    private var analyticsArtifactUploadService: MockAnalyticsArtifactUploadServicing!

    init() {
        createCommandEventService = .init()
        cacheDirectoriesProvider = .init()
        analyticsArtifactUploadService = .init()
        cacheDirectoriesProvider = MockCacheDirectoriesProviding()
    }

    @Test(.withMockedEnvironment(), .inTemporaryDirectory) mutating func testDispatch_sendsToServer() async throws {
        // Given
        let fullHandle = "project"
        let url = URL.test()
        let backend = TuistAnalyticsServerBackend(
            fullHandle: fullHandle,
            url: url,
            createCommandEventService: createCommandEventService,
            fileHandler: FileHandler.shared,
            cacheDirectoriesProvider: cacheDirectoriesProvider,
            analyticsArtifactUploadService: analyticsArtifactUploadService,
            fileSystem: FileSystem()
        )
        subject = TuistAnalyticsDispatcher(
            backend: backend
        )
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.variables = [:]
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
                commandEventId: .value(10),
                serverURL: .value(url)
            )
            .willReturn(())

        given(cacheDirectoriesProvider)
            .cacheDirectory(for: .value(.runs))
            .willReturn(try #require(FileSystem.temporaryTestDirectory))

        // When
        try await withCheckedThrowingContinuation { continuation in
            do {
                try subject.dispatch(event: Self.commandEvent) {
                    continuation.resume(returning: ())
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    static var commandEvent: CommandEvent {
        CommandEvent(
            runId: "run-id",
            name: "event",
            subcommand: nil,
            commandArguments: ["event"],
            durationInMs: 100,
            clientId: "client",
            tuistVersion: "2.0.0",
            swiftVersion: "5.5",
            macOSVersion: "12.0",
            machineHardwareName: "arm64",
            isCI: false,
            status: .success,
            gitCommitSHA: "26f4fda1548502c474642ce63db7630307242312",
            gitRef: nil,
            gitRemoteURLOrigin: "https://github.com/tuist/tuist",
            gitBranch: "main",
            graph: nil,
            previewId: nil,
            resultBundlePath: nil,
            ranAt: Date()
        )
    }

    static func commandEventData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(Self.commandEvent)
    }
}
