import TuistCloud
import TuistCore
import TuistGraph
import TuistSupport

import XCTest
@testable import TuistAnalytics
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class TuistAnalyticsDispatcherTests: TuistUnitTestCase {
    var subject: TuistAnalyticsDispatcher!
    var mockCloudClient: MockCloudClient!
    var requestDispatcher: MockHTTPRequestDispatcher!
    override func setUp() {
        super.setUp()
        mockCloudClient = MockCloudClient()
        requestDispatcher = MockHTTPRequestDispatcher()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func testDispatch_whenCloudAnalyticsIsNil_sendsOnlyToBackbone() throws {
        // Given
        subject = TuistAnalyticsDispatcher(
            cloud: nil,
            requestDispatcher: requestDispatcher
        )

        // When
        let expectation = XCTestExpectation(description: "completion is called")
        try subject.dispatch(event: Self.commandEvent, completion: { expectation.fulfill() })

        // Then
        _ = XCTWaiter.wait(for: [expectation], timeout: 1.0)
        var expectedBackboneRequest = URLRequest(url: URL(string: "https://backbone.tuist.io/command_events.json")!)
        expectedBackboneRequest.httpMethod = "POST"
        expectedBackboneRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        expectedBackboneRequest.httpBody = try Self.commandEventData()
        XCTAssertEqual(requestDispatcher.requests, [expectedBackboneRequest])
    }

    func testDispatch_whenCloudAnalyticsIsDisabled_sendsOnlyToBackbone() throws {
        // Given
        let config = Cloud(url: .test(), projectId: "project", options: [])
        mockCloudClient.mock(error: TestError(""))
        subject = TuistAnalyticsDispatcher(
            cloud: config,
            cloudClient: mockCloudClient,
            requestDispatcher: requestDispatcher
        )

        // When
        let expectation = XCTestExpectation(description: "completion is called")
        try subject.dispatch(event: Self.commandEvent, completion: { expectation.fulfill() })

        // Then
        _ = XCTWaiter.wait(for: [expectation], timeout: 1.0)
        var expectedBackboneRequest = URLRequest(url: URL(string: "https://backbone.tuist.io/command_events.json")!)
        expectedBackboneRequest.httpMethod = "POST"
        expectedBackboneRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        expectedBackboneRequest.httpBody = try Self.commandEventData()
        XCTAssertEqual(requestDispatcher.requests, [expectedBackboneRequest])
        XCTAssertFalse(mockCloudClient.invokedRequest)
    }

    func testDispatch_whenCloudAnalyticsIsEnabled_sendsToBackboneAndCloud() throws {
        // Given
        let projectID = "project"
        let cloudURL = URL.test()
        let config = Cloud(url: cloudURL, projectId: projectID, options: [.analytics])
        mockCloudClient.mock(
            object: (),
            response: .test(statusCode: 200)
        )
        subject = TuistAnalyticsDispatcher(
            cloud: config,
            cloudClient: mockCloudClient,
            requestDispatcher: requestDispatcher
        )

        // When
        let expectation = XCTestExpectation(description: "completion is called")
        try subject.dispatch(event: Self.commandEvent, completion: { expectation.fulfill() })

        // Then
        _ = XCTWaiter.wait(for: [expectation], timeout: 1.0)
        var expectedBackboneRequest = URLRequest(url: URL(string: "https://backbone.tuist.io/command_events.json")!)
        expectedBackboneRequest.httpMethod = "POST"
        expectedBackboneRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        expectedBackboneRequest.httpBody = try Self.commandEventData()
        XCTAssertEqual(requestDispatcher.requests, [expectedBackboneRequest])
        var expectedCloudRequestUrlComponents = URLComponents(url: cloudURL, resolvingAgainstBaseURL: false)!
        expectedCloudRequestUrlComponents.path = "/api/analytics"
        expectedCloudRequestUrlComponents.queryItems = [URLQueryItem(name: "project_id", value: projectID)]
        var expectedCloudRequest = URLRequest(url: expectedCloudRequestUrlComponents.url!)
        expectedCloudRequest.httpMethod = "POST"
        expectedCloudRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        expectedCloudRequest.httpBody = try Self.commandEventData()
        XCTAssertEqual(
            mockCloudClient.invokedRequestParameterList as? [HTTPResource<Void, CloudEmptyResponseError>],
            [
                HTTPResource(
                    request: { expectedCloudRequest },
                    parse: { _, _ in () },
                    parseError: { _, _ in CloudEmptyResponseError() }
                ),
            ]
        )
    }

    static var commandEvent: CommandEvent {
        CommandEvent(
            name: "event",
            subcommand: nil,
            params: [:],
            durationInMs: 100,
            clientId: "client",
            tuistVersion: "2.0.0",
            swiftVersion: "5.5",
            macOSVersion: "12.0",
            machineHardwareName: "arm64",
            isCI: false
        )
    }

    static func commandEventData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(Self.commandEvent)
    }
}
