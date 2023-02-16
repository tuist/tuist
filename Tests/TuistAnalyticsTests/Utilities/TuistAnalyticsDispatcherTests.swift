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
    override func setUp() {
        super.setUp()
        mockCloudClient = MockCloudClient()
    }

    override func tearDown() {
        subject = nil
        mockCloudClient = nil
        super.tearDown()
    }

    func testDispatch_whenCloudAnalyticsIsEnabled_sendsToCloud() throws {
        // Given
        let projectID = "project"
        let cloudURL = URL.test()
        let config = Cloud(url: cloudURL, projectId: projectID, options: [])
        mockCloudClient.mock(
            object: (),
            response: .test(statusCode: 200)
        )
        subject = TuistAnalyticsDispatcher(
            cloud: config,
            cloudClient: mockCloudClient
        )

        // When
        let expectation = XCTestExpectation(description: "completion is called")
        try subject.dispatch(event: Self.commandEvent, completion: { expectation.fulfill() })

        // Then
        _ = XCTWaiter.wait(for: [expectation], timeout: 1.0)
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
            commandArguments: ["event"],
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
