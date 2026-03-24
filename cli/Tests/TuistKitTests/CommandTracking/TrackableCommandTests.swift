import ArgumentParser
import Foundation
import Mockable
import Path
import Testing
import TuistCore
import TuistGit
import TuistLogging
import TuistProcess
import TuistServer
import TuistSupport

@testable import TuistKit
@testable import TuistTesting

struct TrackableCommandTests {
    private var backgroundProcessRunner: MockBackgroundProcessRunning!
    private var gitController: MockGitControlling!
    private let fileHandler = FileHandler.shared

    init() {
        gitController = MockGitControlling()
        backgroundProcessRunner = MockBackgroundProcessRunning()
        given(backgroundProcessRunner)
            .runInBackground(.any, environment: .any)
            .willReturn()
        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(false)

        given(gitController)
            .gitInfo(workingDirectory: .any)
            .willReturn(.test())
    }

    private func makeSubject(
        flag: Bool = true,
        shouldFail: Bool = false,
        analyticsRequired: Bool = false,
        commandArguments: [String] = ["cache", "warm"]
    ) -> TrackableCommand {
        TrackableCommand(
            command: TestCommand(
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
            sessionDirectory: fileHandler.currentPath
        )
    }

    // MARK: - Tests

    @Test func whenCommandFails_uploadsEventWithExpectedInfo() async throws {
        // Given
        let subject = makeSubject(flag: false, shouldFail: true)
        // When
        await #expect(throws: TestCommand.TestError.commandFailed) {
            try await subject.run(
                fullHandle: "tuist/tuist",
                serverURL: .test(),
                shouldTrackAnalytics: true
            )
        }

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

    @Test func whenPathIsInArguments() async throws {
        // Given
        let subject = makeSubject(commandArguments: ["cache", "warm", "--path", "/my-path"])

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

    @Test func whenPathIsInArguments_and_no_fullHandle_is_set() async throws {
        // Given
        let subject = makeSubject(commandArguments: ["cache", "warm", "--path", "/my-path"])

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

    @Test func whenPathIsNotInArguments() async throws {
        // Given
        let subject = makeSubject(commandArguments: ["cache", "warm"])

        // When
        try await subject.run(fullHandle: "tuist/tuist", serverURL: .test(), shouldTrackAnalytics: true)

        // Then
        verify(backgroundProcessRunner)
            .runInBackground(.any, environment: .any)
            .called(1)
        verify(gitController)
            .gitInfo(workingDirectory: .value(fileHandler.currentPath))
            .called(1)
    }
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
