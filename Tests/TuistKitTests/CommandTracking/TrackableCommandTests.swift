import AnyCodable
import ArgumentParser
import Foundation
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
        shouldFail: Bool = false
    ) {
        subject = TrackableCommand(
            command: TestCommand(flag: flag, shouldFail: shouldFail),
            commandArguments: ["cache", "warm"],
            clock: WallClock(),
            asyncQueue: mockAsyncQueue
        )
    }

    // MARK: - Tests

    func test_whenParamsHaveFlagTrue_dispatchesEventWithExpectedParameters() async throws {
        // Given
        makeSubject(flag: true)
        let expectedParams: [String: AnyCodable] = ["flag": true]

        // When
        try await subject.run()

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
        try await subject.run()

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
        await XCTAssertThrowsSpecific(try await subject.run(), TestCommand.TestError.commandFailed)

        // Then
        XCTAssertEqual(mockAsyncQueue.invokedDispatchCount, 1)
        let event = try XCTUnwrap(mockAsyncQueue.invokedDispatchParameters?.event as? CommandEvent)
        XCTAssertEqual(event.name, "test")
        XCTAssertEqual(event.status, .failure("Command failed"))
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
