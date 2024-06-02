import MockableTest
import TuistGraph
import TuistGraphTesting
import TuistLoader
import TuistServer
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CloudCleanServiceTests: TuistUnitTestCase {
    private var cloudSessionController: MockCloudSessionControlling!
    private var cleanCacheService: MockCleanCacheServicing!
    private var configLoader: MockConfigLoading!
    private var subject: CloudCleanService!

    override func setUp() {
        super.setUp()
        cloudSessionController = .init()
        cleanCacheService = .init()
        configLoader = MockConfigLoading()
        subject = CloudCleanService(
            cloudSessionController: cloudSessionController,
            cleanCacheService: cleanCacheService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        cloudSessionController = nil
        cleanCacheService = nil
        configLoader = nil
        subject = nil
        super.tearDown()
    }

    func test_cloud_clean() async throws {
        // Given
        let url = URL(string: "https://cloud.com")!

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(
                Config.test(
                    cloud: Cloud.test(
                        url: url,
                        projectId: "project/slug"
                    )
                )
            )

        given(cleanCacheService)
            .cleanCache(
                serverURL: .value(url),
                fullName: .value("project/slug")
            )
            .willReturn(())

        // When
        try await subject.clean(path: "/some-path")

        // Then
        XCTAssertPrinterOutputContains("Project was successfully cleaned.")
    }
}
