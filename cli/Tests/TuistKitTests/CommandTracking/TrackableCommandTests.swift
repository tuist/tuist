import ArgumentParser
import Foundation
import Mockable
import Path
import TuistCore
import TuistGit
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

    override func setUp() {
        super.setUp()
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

    override func tearDown() {
        subject = nil
        gitController = nil
        backgroundProcessRunner = nil
        super.tearDown()
    }

    private func makeSubject(
        flag: Bool = true,
        shouldFail: Bool = false,
        analyticsRequired: Bool = false,
        commandArguments: [String] = ["cache", "warm"]
    ) {
        subject = TrackableCommand(
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
            backgroundProcessRunner: backgroundProcessRunner
        )
    }

    // MARK: - Tests

    func test_whenCommandFails_uploadsEventWithExpectedInfo() async throws {
        // Given
        makeSubject(flag: false, shouldFail: true)
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
        makeSubject(commandArguments: ["cache", "warm", "--path", "/my-path"])

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
        makeSubject(commandArguments: ["cache", "warm", "--path", "/my-path"])

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
        makeSubject(commandArguments: ["cache", "warm"])

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

        var type: TuistSupport.ErrorType {
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
