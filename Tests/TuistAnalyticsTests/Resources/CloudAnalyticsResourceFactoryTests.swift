import TuistCloud
import TuistCore
import TuistGraph
import TuistSupport

import XCTest
@testable import TuistAnalytics
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class CloudAnalyticsResourceFactoryTests: TuistUnitTestCase {
    var cloud: Cloud!
    var subject: CloudAnalyticsResourceFactory!

    override func setUp() {
        super.setUp()
        cloud = Cloud.test()
        subject = CloudAnalyticsResourceFactory(cloudConfig: cloud)
    }

    override func tearDown() {
        cloud = nil
        subject = nil
        super.tearDown()
    }

    func test_create() throws {
        // Given
        let event = CommandEvent(
            name: "generate",
            subcommand: nil,
            params: [:],
            durationInMs: 20,
            clientId: "123",
            tuistVersion: "1.2.3",
            swiftVersion: "5.1",
            macOSVersion: "10.15",
            machineHardwareName: "darwin",
            isCI: false
        )
        let got = try subject.create(commandEvent: event)

        // When/Then
        XCTAssertHTTPResourceMethod(got, "POST")
        XCTAssertHTTPResourcePath(got, path: "/api/analytics")
        XCTAssertHTTPResourceContainsHeader(got, header: "Content-Type", value: "application/json")
        XCTAssertHTTPResourceURL(got, url: URL(string: cloud.url.absoluteString + "/api/analytics?project_id=123")!)
    }
}
