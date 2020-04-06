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

final class CloudAuthServiceErrorTests: TuistUnitTestCase {
    func test_description_when_missingCloudURL() {
        // Given
        let subject = CloudAuthServiceError.missingCloudURL

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The cloudURL attribute is missing in your project's configuration.")
    }

    func test_type_when_missingCloudURL() {
        // Given
        let subject = CloudAuthServiceError.missingCloudURL

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }
}

final class CloudAuthServiceTests: TuistUnitTestCase {
    var cloudSessionController: MockCloudSessionController!
    var generatorModelLoader: MockGeneratorModelLoader!
    var subject: CloudAuthService!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionController()
        generatorModelLoader = MockGeneratorModelLoader(basePath: FileHandler.shared.currentPath)
        subject = CloudAuthService(cloudSessionController: cloudSessionController,
                                   generatorModelLoader: generatorModelLoader)
    }

    override func tearDown() {
        super.tearDown()
        cloudSessionController = nil
        generatorModelLoader = nil
        subject = nil
    }

    func test_authenticate_when_cloudURL_is_missing() {
        // Given
        generatorModelLoader.mockConfig("") { (_) -> Config in
            Config.test(cloudURL: nil)
        }

        // Then
        XCTAssertThrowsSpecific(try subject.authenticate(), CloudAuthServiceError.missingCloudURL)
    }

    func test_authenticate() throws {
        // Given
        let cloudURL = URL.test()
        generatorModelLoader.mockConfig("") { (_) -> Config in
            Config.test(cloudURL: cloudURL)
        }

        // When
        try subject.authenticate()

        // Then
        XCTAssertTrue(cloudSessionController.authenticateArgs.contains(cloudURL))
    }
}
