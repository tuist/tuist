import Basic
import Foundation
import TuistCloudTesting
import TuistCore
import TuistCoreTesting
import TuistLoader
import TuistLoaderTesting
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CloudLogoutServiceErrorTests: TuistUnitTestCase {
    func test_description_when_missingCloudURL() {
        // Given
        let subject = CloudLogoutServiceError.missingCloudURL

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The cloudURL attribute is missing in your project's configuration.")
    }

    func test_type_when_missingCloudURL() {
        // Given
        let subject = CloudLogoutServiceError.missingCloudURL

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }
}

final class CloudLogoutServiceTests: TuistUnitTestCase {
    var cloudSessionController: MockCloudSessionController!
    var generatorModelLoader: MockGeneratorModelLoader!
    var versionsFetcher: MockVersionsFetcher!
    var subject: CloudLogoutService!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionController()
        generatorModelLoader = MockGeneratorModelLoader(basePath: FileHandler.shared.currentPath)
        versionsFetcher = MockVersionsFetcher()
        subject = CloudLogoutService(cloudSessionController: cloudSessionController,
                                     generatorModelLoader: generatorModelLoader,
                                     versionsFetcher: versionsFetcher)
    }

    override func tearDown() {
        super.tearDown()
        cloudSessionController = nil
        generatorModelLoader = nil
        versionsFetcher = nil
        subject = nil
    }

    func test_printSession_when_cloudURL_is_missing() {
        // Given
        generatorModelLoader.mockConfig("") { (_) -> Config in
            Config.test(cloudURL: nil)
        }

        // Then
        XCTAssertThrowsSpecific(try subject.logout(), CloudLogoutServiceError.missingCloudURL)
    }

    func test_printSession() throws {
        // Given
        let cloudURL = URL.test()
        generatorModelLoader.mockConfig("") { (_) -> Config in
            Config.test(cloudURL: cloudURL)
        }

        // When
        try subject.logout()

        // Then
        XCTAssertTrue(cloudSessionController.logoutArgs.contains(cloudURL))
    }
}
