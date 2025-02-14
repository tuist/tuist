import ArgumentParser
import Foundation
import Mockable
import Path
import TuistAnalytics
import TuistAsyncQueue
import TuistCore
import TuistServer
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class TrackableCommandTests: TuistTestCase {
    private var subject: TrackableCommand!
    private var asyncQueue: MockAsyncQueuing!
    private var gitController: MockGitControlling!

    override func setUp() {
        super.setUp()
        gitController = MockGitControlling()
        asyncQueue = MockAsyncQueuing()
        given(asyncQueue)
            .waitIfCI()
            .willReturn()
        given(asyncQueue)
            .dispatch(event: Parameter<CommandEvent>.any)
            .willReturn()
        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(false)

        given(gitController)
            .ref(environment: .any)
            .willReturn(nil)
    }

    override func tearDown() {
        subject = nil
        gitController = nil
        asyncQueue = nil
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
            asyncQueue: asyncQueue
        )
    }

    // MARK: - Tests

    func test_whenCommandFails_dispatchesEventWithExpectedInfo() async throws {
        // Given
        makeSubject(flag: false, shouldFail: true)
        // When
        await XCTAssertThrowsSpecific(
            try await subject.run(backend: TuistAnalyticsServerBackend(fullHandle: "", url: .test())),
            TestCommand.TestError.commandFailed
        )

        // Then
        verify(asyncQueue)
            .dispatch(event: Parameter<CommandEvent>.matching { event in
                event.name == "test" && event.status == .failure("Command failed")
            })
            .called(1)
    }

    func test_whenPathIsInArguments() async throws {
        // Given
        makeSubject(commandArguments: ["cache", "warm", "--path", "/my-path"])

        // When
        try await subject.run(backend: TuistAnalyticsServerBackend(fullHandle: "", url: .test()))

        // Then
        verify(asyncQueue)
            .dispatch(event: Parameter<CommandEvent>.any)
            .called(1)
        verify(gitController)
            .isInGitRepository(workingDirectory: .value(try AbsolutePath(validating: "/my-path")))
            .called(1)
    }

    func test_whenPathIsInArguments_and_no_backend_is_set() async throws {
        // Given
        makeSubject(commandArguments: ["cache", "warm", "--path", "/my-path"])

        // When
        try await subject.run(backend: nil)

        // Then
        verify(asyncQueue)
            .dispatch(event: Parameter<CommandEvent>.any)
            .called(0)
        verify(gitController)
            .isInGitRepository(workingDirectory: .value(try AbsolutePath(validating: "/my-path")))
            .called(0)
    }

    func test_whenPathIsNotInArguments() async throws {
        // Given
        makeSubject(commandArguments: ["cache", "warm"])

        // When
        try await subject.run(backend: TuistAnalyticsServerBackend(fullHandle: "", url: .test()))

        // Then
        verify(asyncQueue)
            .dispatch(event: Parameter<CommandEvent>.any)
            .called(1)
        verify(gitController)
            .isInGitRepository(workingDirectory: .value(fileHandler.currentPath))
            .called(1)
    }

    func test_when_command_event_is_required_to_be_uploaded() async throws {
        // Given
        given(asyncQueue)
            .wait()
            .willReturn()
        makeSubject(
            analyticsRequired: true
        )

        // When
        try await subject.run(backend: MockTuistServerAnalyticsBackend(fullHandle: "", url: .test()))

        // Then
        verify(asyncQueue)
            .wait()
            .called(0)
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

final class MockTuistServerAnalyticsBackend: TuistAnalyticsServerBackend {
    override func send(commandEvent _: CommandEvent) async throws -> ServerCommandEvent {
        return .test()
    }
}
