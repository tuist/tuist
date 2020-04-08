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

final class CloudSessionServiceErrorTests: TuistUnitTestCase {
    func test_description_when_missingCloudURL() {
        // Given
        let subject = CloudSessionServiceError.missingCloudURL

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The cloudURL attribute is missing in your project's configuration.")
    }

    func test_type_when_missingCloudURL() {
        // Given
        let subject = CloudSessionServiceError.missingCloudURL

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }
}

final class CloudSessionServiceTests: TuistUnitTestCase {
    var cloudSessionController: MockCloudSessionController!
    var generatorModelLoader: MockGeneratorModelLoader!
    var subject: CloudSessionService!
    var versionsFetcher: MockVersionsFetcher!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionController()
        generatorModelLoader = MockGeneratorModelLoader(basePath: FileHandler.shared.currentPath)
        versionsFetcher = MockVersionsFetcher()
        subject = CloudSessionService(cloudSessionController: cloudSessionController,
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
        XCTAssertThrowsSpecific(try subject.printSession(), CloudSessionServiceError.missingCloudURL)
    }

    func test_printSession() throws {
        // Given
        let cloudURL = URL.test()
        generatorModelLoader.mockConfig("") { (_) -> Config in
            Config.test(cloudURL: cloudURL)
        }

        // When
        try subject.printSession()

        // Then
        XCTAssertTrue(cloudSessionController.printSessionArgs.contains(cloudURL))
    }
}
