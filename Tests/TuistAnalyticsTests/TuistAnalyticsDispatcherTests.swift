import TuistCloud
import TuistCore
import TuistGraph
import TuistSupport

@testable import TuistAnalytics
@testable import TuistCoreTesting
@testable import TuistSupportTesting
import XCTest

final class TuistAnalyticsDispatcherTests: TuistUnitTestCase {
    var subject: TuistAnalyticsDispatcher!
    var mockCloudClient: MockCloudClient!
    var requestDispatcher: MockHTTPRequestDispatcher!

    override func setUp() {
        mockCloudClient = MockCloudClient()
        requestDispatcher = MockHTTPRequestDispatcher()
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func testDispatch_whenCloudAnalyticsIsNil_sendsOnlyToBackbone() {
        // Given
        let eventData = "DATA".data(using: .utf8)
        subject = TuistAnalyticsDispatcher(
            cloudDependencies: nil,
            requestDispatcher: requestDispatcher
        )

        // When
        let expectation = XCTestExpectation(description: "completion is called")
        subject.dispatchPersisted(
            data: eventData!,
            completion: {
                expectation.fulfill()
            }
        )

        // Then
        _ = XCTWaiter.wait(for: [expectation], timeout: 1.0)
        var expectedBackboneRequest = URLRequest(url: URL(string: "https://backbone.tuist.io/command_events.json")!)
        expectedBackboneRequest.httpMethod = "POST"
        expectedBackboneRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        expectedBackboneRequest.httpBody = eventData
        XCTAssertEqual(requestDispatcher.requests, [expectedBackboneRequest])
    }

    func testDispatch_whenCloudAnalyticsIsDisabled_sendsOnlyToBackbone() {
        // Given
        let config = Cloud(url: .test(), projectId: "project", options: [])
        let eventData = "DATA".data(using: .utf8)
        mockCloudClient.mock(error: TestError(""))
        subject = TuistAnalyticsDispatcher(
            cloudDependencies: (
                config: config,
                resourceFactory: CloudAnalyticsResourceFactory(cloudConfig: config),
                client: mockCloudClient
            ),
            requestDispatcher: requestDispatcher
        )

        // When
        let expectation = XCTestExpectation(description: "completion is called")
        subject.dispatchPersisted(
            data: eventData!,
            completion: {
                expectation.fulfill()
            }
        )

        // Then
        _ = XCTWaiter.wait(for: [expectation], timeout: 1.0)
        var expectedBackboneRequest = URLRequest(url: URL(string: "https://backbone.tuist.io/command_events.json")!)
        expectedBackboneRequest.httpMethod = "POST"
        expectedBackboneRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        expectedBackboneRequest.httpBody = eventData
        XCTAssertEqual(requestDispatcher.requests, [expectedBackboneRequest])
        XCTAssertFalse(mockCloudClient.invokedRequest)
    }

    func testDispatch_whenCloudAnalyticsIsEnabled_sendsOnlyToBackboneAndCloud() {
        // Given
        let projectID = "project"
        let cloudURL = URL.test()
        let config = Cloud(url: cloudURL, projectId: projectID, options: [.analytics])
        let eventData = "DATA".data(using: .utf8)
        mockCloudClient.mock(
            object: (),
            response: .test(statusCode: 200)
        )
        subject = TuistAnalyticsDispatcher(
            cloudDependencies: (
                config: config,
                resourceFactory: CloudAnalyticsResourceFactory(cloudConfig: config),
                client: mockCloudClient
            ),
            requestDispatcher: requestDispatcher
        )

        // When
        let expectation = XCTestExpectation(description: "completion is called")
        subject.dispatchPersisted(
            data: eventData!,
            completion: {
                expectation.fulfill()
            }
        )

        // Then
        _ = XCTWaiter.wait(for: [expectation], timeout: 1.0)
        var expectedBackboneRequest = URLRequest(url: URL(string:  "https://backbone.tuist.io/command_events.json")!)
        expectedBackboneRequest.httpMethod = "POST"
        expectedBackboneRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        expectedBackboneRequest.httpBody = eventData
        XCTAssertEqual(requestDispatcher.requests, [expectedBackboneRequest])
        var expectedCloudRequestUrlComponents = URLComponents(url: cloudURL, resolvingAgainstBaseURL: false)!
        expectedCloudRequestUrlComponents.path = "/api/analytics"
        expectedCloudRequestUrlComponents.queryItems = [URLQueryItem(name: "project_id", value: projectID)]
        var expectedCloudRequest = URLRequest(url: expectedCloudRequestUrlComponents.url!)
        expectedCloudRequest.httpMethod = "POST"
        expectedCloudRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        expectedCloudRequest.httpBody = eventData
        XCTAssertEqual(
            mockCloudClient.invokedRequestParameterList as? [HTTPResource<Void, CloudEmptyResponseError>],
            [
                HTTPResource(
                    request: { expectedCloudRequest },
                    parse: { _, _ in () },
                    parseError: { _, _ in CloudEmptyResponseError() }
                )
            ]
        )
    }
}
