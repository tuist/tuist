import TuistCloud
import TuistCore
import TuistGraph
import TuistSupport

import XCTest
@testable import TuistAnalytics
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class TuistAnalyticsBackboneBackendTests: TuistUnitTestCase {
    var requestDispatcher: MockHTTPRequestDispatcher!
    var subject: TuistAnalyticsBackboneBackend!

    override func setUp() {
        super.setUp()
        requestDispatcher = MockHTTPRequestDispatcher()
        subject = TuistAnalyticsBackboneBackend(requestDispatcher: requestDispatcher)
    }

    override func tearDown() {
        requestDispatcher = nil
        subject = nil
        super.tearDown()
    }

    func test_resource() throws {
        // Given
        let commandEvent = CommandEvent.test()
        let got = try subject.resource(commandEvent)

        // Then
        XCTAssertHTTPResourceMethod(got, "POST")
        XCTAssertHTTPResourceURL(got, url: Constants.backboneURL.appendingPathComponent("command_events.json"))
        XCTAssertHTTPResourceContainsHeader(got, header: "Content-Type", value: "application/json")
    }

    func test_send() async throws {
        // Given
        let commandEvent = CommandEvent.test()

        // When
        try await subject.send(commandEvent: commandEvent)
    }
}
