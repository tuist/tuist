import ArgumentParser
import Foundation
import Mockable
import Path
import TuistAlert
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistGit
import TuistJobSummary
import TuistLogging
import TuistProcess
import TuistServer
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistTesting

final class TrackableCommandTests: TuistTestCase {
    private var subject: TrackableCommand!
    private var backgroundProcessRunner: MockBackgroundProcessRunning!
    private var gitController: MockGitControlling!
    private var serverAuthenticationController: MockServerAuthenticationControlling!
    private var uploadAnalyticsService: MockUploadAnalyticsServicing!
    private var gitHubActionsJobSummaryService: MockGitHubActionsJobSummaryServicing!

    override func setUp() {
        super.setUp()
        gitController = MockGitControlling()
        backgroundProcessRunner = MockBackgroundProcessRunning()
        serverAuthenticationController = MockServerAuthenticationControlling()
        uploadAnalyticsService = MockUploadAnalyticsServicing()
        gitHubActionsJobSummaryService = MockGitHubActionsJobSummaryServicing()
        given(backgroundProcessRunner)
            .runInBackground(.any, environment: .any)
            .willReturn()
        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(false)

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test())

        given(uploadAnalyticsService)
            .upload(commandEvent: .any, fullHandle: .any, serverURL: .any, sessionDirectory: .any)
            .willReturn(.test())

        given(gitHubActionsJobSummaryService)
            .writeJobSummary(testRunReports: .any, buildRunReports: .any, runURL: .any)
            .willReturn()
    }

    override func tearDown() {
        subject = nil
        gitController = nil
        backgroundProcessRunner = nil
        serverAuthenticationController = nil
        uploadAnalyticsService = nil
        gitHubActionsJobSummaryService = nil
        super.tearDown()
    }

    private func makeSubject(
        command: ParsableCommand? = nil,
        flag: Bool = true,
        shouldFail: Bool = false,
        analyticsRequired: Bool = false,
        commandArguments: [String] = ["cache", "warm"],
        uploadAnalyticsService: UploadAnalyticsServicing? = nil,
        bestEffortForegroundUploadTimeout: Duration = .seconds(15)
    ) throws {
        let temporaryPath = try temporaryPath()
        subject = TrackableCommand(
            command: command ?? TestCommand(
                flag: flag,
                shouldFail: shouldFail,
                analyticsRequired: analyticsRequired
            ),
            commandArguments: commandArguments,
            clock: WallClock(),
            commandEventFactory: CommandEventFactory(
                gitController: gitController
            ),
            backgroundProcessRunner: backgroundProcessRunner,
            uploadAnalyticsService: uploadAnalyticsService ?? self.uploadAnalyticsService,
            serverAuthenticationController: serverAuthenticationController,
            gitHubActionsJobSummaryService: gitHubActionsJobSummaryService,
            bestEffortForegroundUploadTimeout: bestEffortForegroundUploadTimeout,
            sessionDirectory: temporaryPath
        )
    }

    // MARK: - Tests

    func test_whenCommandFails_uploadsEventWithExpectedInfo() async throws {
        // Given
        try makeSubject(flag: false, shouldFail: true)
        // When
        await XCTAssertThrowsSpecific(
            try await subject.run(
                fullHandle: "tuist/tuist",
                serverURL: .test(),
                shouldTrackAnalytics: true
            ),
            TestCommand.TestError.commandFailed
        )

        // Then
        verify(backgroundProcessRunner)
            .runInBackground(
                .matching { arguments in
                    arguments.contains("analytics-upload")
                },
                environment: .any
            )
            .called(1)
    }

    func test_whenPathIsInArguments() async throws {
        // Given
        try makeSubject(commandArguments: ["cache", "warm", "--path", "/my-path"])

        // When
        try await subject.run(fullHandle: "tuist/tuist", serverURL: .test(), shouldTrackAnalytics: true)

        // Then
        verify(backgroundProcessRunner)
            .runInBackground(.any, environment: .any)
            .called(1)
        verify(gitController)
            .gitInfo(workingDirectory: .value(try AbsolutePath(validating: "/my-path")))
            .called(1)
    }

    func test_whenPathIsInArguments_and_no_fullHandle_is_set() async throws {
        // Given
        try makeSubject(commandArguments: ["cache", "warm", "--path", "/my-path"])

        // When
        try await subject.run(fullHandle: nil, serverURL: .test(), shouldTrackAnalytics: true)

        // Then
        verify(backgroundProcessRunner)
            .runInBackground(.any, environment: .any)
            .called(0)
        verify(gitController)
            .isInGitRepository(workingDirectory: .value(try AbsolutePath(validating: "/my-path")))
            .called(0)
    }

    func test_whenPathIsNotInArguments() async throws {
        // Given
        try makeSubject(commandArguments: ["cache", "warm"])

        // When
        try await subject.run(fullHandle: "tuist/tuist", serverURL: .test(), shouldTrackAnalytics: true)

        // Then
        verify(backgroundProcessRunner)
            .runInBackground(.any, environment: .any)
            .called(1)
        verify(gitController)
            .gitInfo(workingDirectory: .any)
            .called(1)
    }

    func test_whenOptionalAuthenticationIsEnabled_forTrackedCommands_wraps_command_execution() async throws {
        // Given
        let recorder = AuthenticationConfigRecorder()
        ConfigObservingCommandState.recorder = recorder
        ConfigObservingCommandState.analyticsRequired = true
        let command = ConfigObservingCommand()
        try makeSubject(command: command)

        // When
        try await subject.run(
            fullHandle: nil,
            serverURL: nil,
            shouldTrackAnalytics: false,
            optionalAuthentication: true
        )

        // Then
        let recordedValues = await recorder.values()
        XCTAssertEqual(recordedValues, [true])
    }

    func test_whenOptionalAuthenticationIsEnabled_andNoToken_skipsForegroundUpload() async throws {
        // Given
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any, refreshIfNeeded: .any)
            .willReturn(nil)
        try makeSubject(analyticsRequired: true)

        // When
        try await subject.run(
            fullHandle: "tuist/tuist",
            serverURL: .test(),
            shouldTrackAnalytics: true,
            optionalAuthentication: true
        )

        // Then
        verify(uploadAnalyticsService)
            .upload(commandEvent: .any, fullHandle: .any, serverURL: .any, sessionDirectory: .any)
            .called(0)
        verify(backgroundProcessRunner)
            .runInBackground(.any, environment: .any)
            .called(0)
    }

    func test_whenOptionalAuthenticationIsEnabled_andTokenIsAvailable_uploadsRunMetadata() async throws {
        // Given
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any, refreshIfNeeded: .any)
            .willReturn(.project("token"))
        try makeSubject(analyticsRequired: true)

        // When
        try await subject.run(
            fullHandle: "tuist/tuist",
            serverURL: .test(),
            shouldTrackAnalytics: true,
            optionalAuthentication: true
        )

        // Then
        verify(uploadAnalyticsService)
            .upload(commandEvent: .any, fullHandle: .any, serverURL: .any, sessionDirectory: .any)
            .called(1)
    }

    func test_whenRunMetadataUploadTimesOut_doesNotFailCommand() async throws {
        // Given
        uploadAnalyticsService.reset()
        given(uploadAnalyticsService)
            .upload(commandEvent: .any, fullHandle: .any, serverURL: .any, sessionDirectory: .any)
            .willThrow(URLError(.timedOut))
        try makeSubject(analyticsRequired: true)

        // When/Then
        try await subject.run(
            fullHandle: "tuist/tuist",
            serverURL: .test(),
            shouldTrackAnalytics: true
        )
    }

    func test_whenRunMetadataCreationFails_doesNotFailCommand() async throws {
        // Given
        gitController.reset()
        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willThrow(NSError(domain: "TestDomain", code: 525))
        try makeSubject(analyticsRequired: true)

        // When/Then
        try await subject.run(
            fullHandle: "tuist/tuist",
            serverURL: .test(),
            shouldTrackAnalytics: true
        )

        verify(uploadAnalyticsService)
            .upload(commandEvent: .any, fullHandle: .any, serverURL: .any, sessionDirectory: .any)
            .called(0)
    }

    func test_whenCommandConfigurationHasNoName_usesArgumentsAsFallbackName() async throws {
        // Given
        try makeSubject(
            command: UnnamedCommand(),
            commandArguments: ["mystery"]
        )
        let alertController = AlertController()

        // When
        try await AlertController.$current.withValue(alertController) {
            try await subject.run(
                fullHandle: "tuist/tuist",
                serverURL: .test(),
                shouldTrackAnalytics: true
            )
        }

        // Then
        verify(uploadAnalyticsService)
            .upload(
                commandEvent: .matching { event in
                    event.name == "mystery" && event.subcommand == nil
                },
                fullHandle: .any,
                serverURL: .any,
                sessionDirectory: .any
            )
            .called(1)
        XCTAssertEqual(alertController.warnings().count, 1)
        XCTAssertEqual(
            alertController.warnings().first?.message.plain(),
            "Failed to resolve canonical command metadata for analytics. Falling back to command arguments."
        )
    }

    func test_whenCommandStoresResolvedAnalyticsMetadata_uploadsCanonicalValues() async throws {
        // Given
        try makeSubject(
            command: ResolvedMetadataCommand(),
            commandArguments: ["xcodebuild", "-workspace", "App.xcworkspace", "build"]
        )

        // When
        try await subject.run(
            fullHandle: "tuist/tuist",
            serverURL: .test(),
            shouldTrackAnalytics: true
        )

        // Then
        verify(uploadAnalyticsService)
            .upload(
                commandEvent: .matching { event in
                    event.name == "xcodebuild" &&
                        event.subcommand == "build" &&
                        event.commandArguments == ["xcodebuild", "build", "-workspace", "App.xcworkspace"]
                },
                fullHandle: .any,
                serverURL: .any,
                sessionDirectory: .any
            )
            .called(1)
    }

    func test_whenOptionalAuthenticationIsEnabled_background_upload_does_not_add_a_flag() async throws {
        // Given
        try makeSubject(analyticsRequired: false)

        // When
        try await subject.run(
            fullHandle: "tuist/tuist",
            serverURL: .test(),
            shouldTrackAnalytics: true,
            optionalAuthentication: true
        )

        // Then
        verify(backgroundProcessRunner)
            .runInBackground(
                .matching { arguments in
                    !arguments.contains("--optional-authentication")
                },
                environment: .any
            )
            .called(1)
    }

    func test_whenForegroundUpload_writesGitHubActionsJobSummary() async throws {
        // Given
        try makeSubject(analyticsRequired: true)

        // When
        try await subject.run(
            fullHandle: "tuist/tuist",
            serverURL: .test(),
            shouldTrackAnalytics: true
        )

        // Then
        verify(gitHubActionsJobSummaryService)
            .writeJobSummary(testRunReports: .any, buildRunReports: .any, runURL: .any)
            .called(1)
    }

    func test_whenBestEffortForegroundUploadTimesOut_doesNotWriteGitHubActionsJobSummary() async throws {
        // Given
        try await withMockedEnvironment {
            Environment.mocked?.variables["CI"] = "true"
            let delayedUploadAnalyticsService = DelayedUploadAnalyticsService(delay: .seconds(1))
            try makeSubject(
                analyticsRequired: false,
                uploadAnalyticsService: delayedUploadAnalyticsService,
                bestEffortForegroundUploadTimeout: .milliseconds(1)
            )

            // When
            try await subject.run(
                fullHandle: "tuist/tuist",
                serverURL: .test(),
                shouldTrackAnalytics: true
            )

            // Then
            verify(gitHubActionsJobSummaryService)
                .writeJobSummary(testRunReports: .any, buildRunReports: .any, runURL: .any)
                .called(0)
        }
    }

    func test_whenBackgroundUpload_doesNotWriteGitHubActionsJobSummary() async throws {
        // Given
        try makeSubject(analyticsRequired: false)

        // When
        try await subject.run(
            fullHandle: "tuist/tuist",
            serverURL: .test(),
            shouldTrackAnalytics: true
        )

        // Then
        verify(gitHubActionsJobSummaryService)
            .writeJobSummary(testRunReports: .any, buildRunReports: .any, runURL: .any)
            .called(0)
    }
}

private struct DelayedUploadAnalyticsService: UploadAnalyticsServicing {
    let delay: Duration

    @discardableResult
    func upload(
        commandEvent _: CommandEvent,
        fullHandle _: String,
        serverURL _: URL,
        sessionDirectory _: AbsolutePath?
    ) async throws -> ServerCommandEvent {
        try await Task.sleep(for: delay)
        return .test()
    }
}

private actor AuthenticationConfigRecorder {
    private var recordedValues: [Bool] = []

    func record(_ value: Bool) {
        recordedValues.append(value)
    }

    func values() -> [Bool] {
        recordedValues
    }
}

private enum ConfigObservingCommandState {
    static var recorder = AuthenticationConfigRecorder()
    static var analyticsRequired = false
}

private struct TestCommand: TrackableParsableCommand, ParsableCommand {
    enum TestError: FatalError, Equatable {
        case commandFailed

        var type: ErrorType {
            switch self {
            case .commandFailed:
                return .abort
            }
        }

        var description: String {
            "Command failed"
        }
    }

    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "test")
    }

    var flag: Bool = false
    var shouldFail: Bool = false
    var analyticsRequired: Bool = false

    func run() throws {
        if shouldFail {
            throw TestError.commandFailed
        }
    }
}

private struct ConfigObservingCommand: TrackableParsableCommand, AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "observe")
    }

    var analyticsRequired: Bool {
        ConfigObservingCommandState.analyticsRequired
    }

    func run() async throws {
        await ConfigObservingCommandState.recorder.record(ServerAuthenticationConfig.current.optionalAuthentication)
    }
}

private struct UnnamedCommand: TrackableParsableCommand, ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration()
    }

    var analyticsRequired: Bool { true }

    func run() throws {}
}

private struct ResolvedMetadataCommand: TrackableParsableCommand, AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration()
    }

    var analyticsRequired: Bool { true }

    func run() async throws {
        await RunMetadataStorage.current.update(
            resolvedCommandMetadata: AnalyticsCommandMetadata(
                name: "xcodebuild",
                subcommand: "build",
                commandArguments: ["xcodebuild", "build", "-workspace", "App.xcworkspace"]
            )
        )
    }
}
