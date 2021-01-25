import Foundation
import TSCBasic
import TuistCloudTesting
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
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
        XCTAssertEqual(got, "The cloud URL attribute is missing in your project's configuration.")
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

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionController()
        generatorModelLoader = MockGeneratorModelLoader(basePath: FileHandler.shared.currentPath)
        subject = CloudSessionService(cloudSessionController: cloudSessionController,
                                      generatorModelLoader: generatorModelLoader)
    }

    override func tearDown() {
        super.tearDown()
        cloudSessionController = nil
        generatorModelLoader = nil
        subject = nil
    }

    func test_printSession_when_cloudURL_is_missing() {
        // Given
        generatorModelLoader.mockConfig("") { (_) -> Config in
            Config.test(cloud: nil)
        }

        // Then
        XCTAssertThrowsSpecific(try subject.printSession(), CloudSessionServiceError.missingCloudURL)
    }

    func test_printSession() throws {
        // Given
        let cloudURL = URL.test()
        generatorModelLoader.mockConfig("") { (_) -> Config in
            Config.test(cloud: Cloud(url: cloudURL, projectId: "123", options: []))
        }

        // When
        try subject.printSession()

        // Then
        XCTAssertTrue(cloudSessionController.printSessionArgs.contains(cloudURL))
    }
}
