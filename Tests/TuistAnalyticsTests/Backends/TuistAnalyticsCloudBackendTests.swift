import TuistCloud
import TuistCore
import TuistGraph
import TuistSupport

import XCTest
@testable import TuistAnalytics
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class TuistAnalyticsCloudBackendTests: TuistUnitTestCase {
    var config: Cloud!
    var resourceFactory: MockCloudAnalyticsResourceFactory!
    var client: MockCloudClient!
    var subject: TuistAnalyticsCloudBackend!

    override func setUp() {
        super.setUp()
        config = Cloud.test()
        resourceFactory = MockCloudAnalyticsResourceFactory()
        client = MockCloudClient()
        subject = TuistAnalyticsCloudBackend(
            config: config,
            resourceFactory: resourceFactory,
            client: client
        )
    }

    override func tearDown() {
        config = nil
        resourceFactory = nil
        client = nil
        subject = nil
        super.tearDown()
    }

    func test_send_when_analytics_is_not_enabled() async throws {
        // Given
        config = Cloud.test(options: [.disableAnalytics])
        subject = TuistAnalyticsCloudBackend(
            config: config,
            resourceFactory: resourceFactory,
            client: client
        )
        let event = CommandEvent.test()

        // When
        try await subject.send(commandEvent: event)

        // Then
        XCTAssertEqual(resourceFactory.invokedCreateCount, 0)
    }

    func test_send_when_analytics_is_enabled() async throws {
        // Given
        config = Cloud.test()
        subject = TuistAnalyticsCloudBackend(
            config: config,
            resourceFactory: resourceFactory,
            client: client
        )
        let resource = HTTPResource<Void, CloudEmptyResponseError>.void()
        resourceFactory.stubbedCreateResult = resource
        let event = CommandEvent.test()
        client.stubbedObjectPerURLRequest[resource.request()] = ()
        client.stubbedResponsePerURLRequest[resource.request()] = HTTPURLResponse.test()

        // When
        try await subject.send(commandEvent: event)

        // Then
        XCTAssertEqual(resourceFactory.invokedCreateCount, 1)
    }
}
