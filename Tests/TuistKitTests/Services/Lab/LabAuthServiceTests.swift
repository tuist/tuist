import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import TuistLabTesting
import TuistLoader
import TuistLoaderTesting
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class LabAuthServiceErrorTests: TuistUnitTestCase {
    func test_description_when_missingScaleURL() {
        // Given
        let subject = LabAuthServiceError.missingLabURL

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The lab URL attribute is missing in your project's configuration.")
    }

    func test_type_when_missingCloudURL() {
        // Given
        let subject = LabAuthServiceError.missingLabURL

        // When
        let got = subject.type

        // Then
        XCTAssertEqual(got, .abort)
    }
}

final class LabAuthServiceTests: TuistUnitTestCase {
    var labSessionController: MockLabSessionController!
    var configLoader: MockConfigLoader!
    var subject: LabAuthService!

    override func setUp() {
        super.setUp()
        labSessionController = MockLabSessionController()
        configLoader = MockConfigLoader()
        subject = LabAuthService(
            labSessionController: labSessionController,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        super.tearDown()
        labSessionController = nil
        configLoader = nil
        subject = nil
    }

    func test_authenticate_when_cloudURL_is_missing() {
        // Given
        configLoader.loadConfigStub = { _ in
            Config.test(lab: nil)
        }

        // Then
        XCTAssertThrowsSpecific(try subject.authenticate(), LabAuthServiceError.missingLabURL)
    }

    func test_authenticate() throws {
        // Given
        let labURL = URL.test()
        configLoader.loadConfigStub = { _ in
            Config.test(lab: Lab(url: labURL, projectId: "123", options: []))
        }

        // When
        try subject.authenticate()

        // Then
        XCTAssertTrue(labSessionController.authenticateArgs.contains(labURL))
    }
}
