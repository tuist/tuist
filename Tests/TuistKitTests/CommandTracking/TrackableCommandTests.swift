import ArgumentParser
import Foundation
import TuistSupport
import XCTest
import TuistAsyncQueueTesting
import TuistAnalytics

@testable import TuistKit
@testable import TuistSupportTesting

final class TrackableCommandTests: TuistUnitTestCase {
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

    private func makeSubject(flag: Bool = true) {
        subject = TrackableCommand(command: TestCommand(flag: flag),
                                   clock: WallClock(),
                                   asyncQueue: mockAsyncQueue)
    }

    // MARK: - Tests

    func test_whenParamsHaveFlagTrue_dispatchesEventWithExpectedParameters() throws {
        // Given
        makeSubject(flag: true)
        let expectedParams = ["flag": "true"]

        // When
        try subject.run(completion: {})

        // Then
        XCTAssertEqual(mockAsyncQueue.invokedDispatchCount, 1)
        let event = try XCTUnwrap(mockAsyncQueue.invokedDispatchParameters?.event as? CommandEvent)
        XCTAssertEqual(event.name, "test")
        XCTAssertEqual(event.params, expectedParams)
    }

    func test_whenParamsHaveFlagFalse_dispatchesEventWithExpectedParameters() throws {
        // Given
        makeSubject(flag: false)
        let expectedParams = ["flag": "false"]

        // When
        try subject.run(completion: {})

        // Then
        XCTAssertEqual(mockAsyncQueue.invokedDispatchCount, 1)
        let event = try XCTUnwrap(mockAsyncQueue.invokedDispatchParameters?.event as? CommandEvent)
        XCTAssertEqual(event.name, "test")
        XCTAssertEqual(event.params, expectedParams)
    }
}

private struct TestCommand: ParsableCommand, HasTrackableParameters {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "test")
    }

    var flag: Bool = false

    static var analyticsDelegate: TrackableParametersDelegate?

    func run() throws {
        TestCommand.analyticsDelegate?.willRun(withParameters: ["flag": String(flag)])
    }
}
