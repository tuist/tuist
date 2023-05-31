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
    private var cleanRemoteCacheStorageService: MockCleanRemoteCacheStorageService!
    private var configLoader: MockConfigLoader!
    private var subject: CloudCleanService!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionController()
        cleanRemoteCacheStorageService = MockCleanRemoteCacheStorageService()
        configLoader = MockConfigLoader()
        subject = CloudCleanService(
            cloudSessionController: cloudSessionController,
            cleanRemoteCacheStorageService: cleanRemoteCacheStorageService,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        cloudSessionController = nil
        cleanRemoteCacheStorageService = nil
        configLoader = nil
        subject = nil
        super.tearDown()
    }

    func test_cloud_clean() async throws {
        // Given
        var cleanedProjectURL: URL?
        var cleanedProjectSlug: String?
        cleanRemoteCacheStorageService.cleanRemoteCacheStorageStub = {
            cleanedProjectURL = $0
            cleanedProjectSlug = $1
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
        XCTAssertEqual(cleanedProjectSlug, "project/slug")
        XCTAssertPrinterOutputContains("Project was successfully cleaned.")
    }
}
