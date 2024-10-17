import AnyCodable
import ArgumentParser
import Foundation
import MockableTest
import Path
import TuistAnalytics
import TuistAsyncQueueTesting
import TuistCore
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class TrackableCommandTests: TuistTestCase {
    private var subject: TrackableCommand!
    private var mockAsyncQueue: MockAsyncQueuer!
    private var gitController: MockGitControlling!

    override func setUp() {
        super.setUp()
        mockAsyncQueue = MockAsyncQueuer()
    }

    override func tearDown() {
        subject = nil
        mockAsyncQueue = nil
        super.tearDown()
    }

    private func makeSubject(
        flag: Bool = true,
        shouldFail: Bool = false,
        commandArguments: [String] = ["cache", "warm"]
    ) {
        gitController = MockGitControlling()
        subject = TrackableCommand(
            command: TestCommand(flag: flag, shouldFail: shouldFail),
            commandArguments: commandArguments,
            clock: WallClock(),
            commandEventFactory: CommandEventFactory(
                gitController: gitController
            ),
            asyncQueue: mockAsyncQueue
        )

        given(gitController)
            .isInGitRepository(workingDirectory: .any)
            .willReturn(false)

        given(gitController)
            .ref(environment: .any)
            .willReturn(nil)
    }

    // MARK: - Tests

    func test_whenParamsHaveFlagTrue_dispatchesEventWithExpectedParameters() async throws {
        // Given
        makeSubject(flag: true)
        let expectedParams: [String: AnyCodable] = ["flag": true]

        // When
        try await subject.run(analyticsEnabled: true)

        // Then
        XCTAssertEqual(mockAsyncQueue.invokedDispatchCount, 1)
        let event = try XCTUnwrap(mockAsyncQueue.invokedDispatchParameters?.event as? CommandEvent)
        XCTAssertEqual(event.name, "test")
        XCTAssertEqual(event.params, expectedParams)
    }

    func test_whenParamsHaveFlagFalse_dispatchesEventWithExpectedParameters() async throws {
        // Given
        makeSubject(flag: false)
        let expectedParams: [String: AnyCodable] = ["flag": false]
        // When
        try await subject.run(analyticsEnabled: true)

        // Then
        XCTAssertEqual(mockAsyncQueue.invokedDispatchCount, 1)
        let event = try XCTUnwrap(mockAsyncQueue.invokedDispatchParameters?.event as? CommandEvent)
        XCTAssertEqual(event.name, "test")
        XCTAssertEqual(event.params, expectedParams)
    }

    func test_whenCommandFails_dispatchesEventWithExpectedInfo() async throws {
        // Given
        makeSubject(flag: false, shouldFail: true)
        // When
        await XCTAssertThrowsSpecific(try await subject.run(analyticsEnabled: true), TestCommand.TestError.commandFailed)

        // Then
        XCTAssertEqual(mockAsyncQueue.invokedDispatchCount, 1)
        let event = try XCTUnwrap(mockAsyncQueue.invokedDispatchParameters?.event as? CommandEvent)
        XCTAssertEqual(event.name, "test")
        XCTAssertEqual(event.status, .failure("Command failed"))
    }

    func test_whenPathIsInArguments() async throws {
        // Given
        makeSubject(commandArguments: ["cache", "warm", "--path", "/my-path"])

        // When
        try await subject.run(analyticsEnabled: true)

        // Then
        XCTAssertEqual(mockAsyncQueue.invokedDispatchCount, 1)
        verify(gitController)
            .isInGitRepository(workingDirectory: .value(try AbsolutePath(validating: "/my-path")))
            .called(1)
    }

    func test_whenPathIsInArguments_and_analytics_are_disabled() async throws {
        // Given
        makeSubject(commandArguments: ["cache", "warm", "--path", "/my-path"])

        // When
        try await subject.run(analyticsEnabled: false)

        // Then
        XCTAssertEqual(mockAsyncQueue.invokedDispatchCount, 0)
        verify(gitController)
            .isInGitRepository(workingDirectory: .value(try AbsolutePath(validating: "/my-path")))
            .called(0)
    }

    func test_whenPathIsNotInArguments() async throws {
        // Given
        makeSubject(commandArguments: ["cache", "warm"])

        // When
        try await subject.run(analyticsEnabled: true)

        // Then
        XCTAssertEqual(mockAsyncQueue.invokedDispatchCount, 1)
        verify(gitController)
            .isInGitRepository(workingDirectory: .value(fileHandler.currentPath))
            .called(1)
    }
}

private struct TestCommand: ParsableCommand, HasTrackableParameters {
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

    static var analyticsDelegate: TrackableParametersDelegate?
    var runId = ""

    func run() throws {
        if shouldFail {
            throw TestError.commandFailed
        }
        TestCommand.analyticsDelegate?.addParameters(["flag": AnyCodable(flag)])
    }
}
