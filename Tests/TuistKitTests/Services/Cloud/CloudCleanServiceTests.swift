import TuistCloudTesting
import TuistGraph
import TuistGraphTesting
import TuistLoaderTesting
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CloudCleanServiceTests: TuistUnitTestCase {
    private var cloudSessionController: MockCloudSessionController!
    private var cleanCacheService: MockCleanCacheService!
    private var configLoader: MockConfigLoader!
    private var subject: CloudCleanService!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionController()
        cleanCacheService = MockCleanCacheService()
        configLoader = MockConfigLoader()
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
        var cleanedProjectURL: URL?
        var cleanedFullName: String?
        cleanCacheService.cleanCacheStub = {
            cleanedProjectURL = $0
            cleanedFullName = $1
        }
        let url = URL(string: "https://cloud.com")!

        configLoader.loadConfigStub = { _ in
            Config.test(
                cloud: Cloud.test(
                    url: url,
                    projectId: "project/slug"
                )
            )
        }

        // When
        try await subject.clean(path: "/some-path")

        // Then
        XCTAssertEqual(cleanedProjectURL?.absoluteString, url.absoluteString)
        XCTAssertEqual(cleanedFullName, "project/slug")
        XCTAssertPrinterOutputContains("Project was successfully cleaned.")
    }
}
