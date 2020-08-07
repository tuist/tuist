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

final class ScaleLogoutServiceErrorTests: TuistUnitTestCase {
    func test_description_when_missingScaleURL() {
        // Given
        let subject = ScaleLogoutServiceError.missingScaleURL

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The scale URL attribute is missing in your project's configuration.")
    }

    func test_type_when_missingScaleURL() {
        // Given
        let subject = ScaleLogoutServiceError.missingScaleURL

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }
}

final class CloudLogoutServiceTests: TuistUnitTestCase {
    var scaleSessionController: MockScaleSessionController!
    var generatorModelLoader: MockGeneratorModelLoader!
    var subject: ScaleLogoutService!

    override func setUp() {
        super.setUp()
        scaleSessionController = MockScaleSessionController()
        generatorModelLoader = MockGeneratorModelLoader(basePath: FileHandler.shared.currentPath)
        subject = ScaleLogoutService(scaleSessionController: scaleSessionController,
                                     generatorModelLoader: generatorModelLoader)
    }

    override func tearDown() {
        super.tearDown()
        scaleSessionController = nil
        generatorModelLoader = nil
        subject = nil
    }

    func test_printSession_when_cloudURL_is_missing() {
        // Given
        generatorModelLoader.mockConfig("") { (_) -> Config in
            Config.test(scale: nil)
        }

        // Then
        XCTAssertThrowsSpecific(try subject.logout(), ScaleLogoutServiceError.missingScaleURL)
    }

    func test_printSession() throws {
        // Given
        let scaleURL = URL.test()
        generatorModelLoader.mockConfig("") { (_) -> Config in
            Config.test(scale: Scale(url: scaleURL, projectId: "123", options: []))
        }

        // When
        try subject.logout()

        // Then
        XCTAssertTrue(scaleSessionController.logoutArgs.contains(scaleURL))
    }
}
