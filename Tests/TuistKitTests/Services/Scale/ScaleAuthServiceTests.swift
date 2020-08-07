import Foundation
import TSCBasic
import TuistCloudTesting
import TuistCore
import TuistCoreTesting
import TuistLoader
import TuistLoaderTesting
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class ScaleAuthServiceErrorTests: TuistUnitTestCase {
    func test_description_when_missingScaleURL() {
        // Given
        let subject = CloudAuthServiceError.missingScaleURL

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The scale URL attribute is missing in your project's configuration.")
    }

    func test_type_when_missingCloudURL() {
        // Given
        let subject = CloudAuthServiceError.missingScaleURL

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }
}

final class CloudAuthServiceTests: TuistUnitTestCase {
    var scaleSessionController: MockScaleSessionController!
    var generatorModelLoader: MockGeneratorModelLoader!
    var subject: CloudAuthService!

    override func setUp() {
        super.setUp()
        scaleSessionController = MockScaleSessionController()
        generatorModelLoader = MockGeneratorModelLoader(basePath: FileHandler.shared.currentPath)
        subject = CloudAuthService(scaleSessionController: scaleSessionController,
                                   generatorModelLoader: generatorModelLoader)
    }

    override func tearDown() {
        super.tearDown()
        scaleSessionController = nil
        generatorModelLoader = nil
        subject = nil
    }

    func test_authenticate_when_cloudURL_is_missing() {
        // Given
        generatorModelLoader.mockConfig("") { (_) -> Config in
            Config.test(scale: nil)
        }

        // Then
        XCTAssertThrowsSpecific(try subject.authenticate(), CloudAuthServiceError.missingScaleURL)
    }

    func test_authenticate() throws {
        // Given
        let scaleURL = URL.test()
        generatorModelLoader.mockConfig("") { (_) -> Config in
            Config.test(scale: Scale(url: scaleURL, projectId: "123", options: []))
        }

        // When
        try subject.authenticate()

        // Then
        XCTAssertTrue(scaleSessionController.authenticateArgs.contains(scaleURL))
    }
}
