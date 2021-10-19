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

final class CloudAuthServiceErrorTests: TuistUnitTestCase {
    func test_description_when_missingScaleURL() {
        // Given
        let subject = CloudAuthServiceError.missingCloudURL

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The cloud URL attribute is missing in your project's configuration.")
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
    var configLoader: MockConfigLoader!
    var subject: CloudAuthService!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionController()
        configLoader = MockConfigLoader()
        subject = CloudAuthService(
            cloudSessionController: cloudSessionController,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        cloudSessionController = nil
        configLoader = nil
        subject = nil
        super.tearDown()
    }

    func test_authenticate_when_cloudURL_is_missing() {
        // Given
        configLoader.loadConfigStub = { _ in
            Config.test(cloud: nil)
        }

        // Then
        XCTAssertThrowsSpecific(try subject.authenticate(), CloudAuthServiceError.missingCloudURL)
    }

    func test_authenticate() throws {
        // Given
        let cloudURL = URL.test()
        configLoader.loadConfigStub = { _ in
            Config.test(cloud: Cloud(url: cloudURL, projectId: "123", options: []))
        }

        // When
        try subject.authenticate()

        // Then
        XCTAssertTrue(cloudSessionController.authenticateArgs.contains(cloudURL))
    }
}
