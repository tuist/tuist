import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistLoader
import TuistLoaderTesting
import TuistScaleTesting
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class ScaleAuthServiceErrorTests: TuistUnitTestCase {
    func test_description_when_missingScaleURL() {
        // Given
        let subject = ScaleAuthServiceError.missingScaleURL

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The scale URL attribute is missing in your project's configuration.")
    }

    func test_type_when_missingCloudURL() {
        // Given
        let subject = ScaleAuthServiceError.missingScaleURL

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }
}

final class CloudAuthServiceTests: TuistUnitTestCase {
    var scaleSessionController: MockScaleSessionController!
    var generatorModelLoader: MockGeneratorModelLoader!
    var subject: ScaleAuthService!

    override func setUp() {
        super.setUp()
        scaleSessionController = MockScaleSessionController()
        generatorModelLoader = MockGeneratorModelLoader(basePath: FileHandler.shared.currentPath)
        subject = ScaleAuthService(scaleSessionController: scaleSessionController,
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
        XCTAssertThrowsSpecific(try subject.authenticate(), ScaleAuthServiceError.missingScaleURL)
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
