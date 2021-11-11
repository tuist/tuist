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

final class CloudLogoutServiceErrorTests: TuistUnitTestCase {
    func test_description_when_missingScaleURL() {
        // Given
        let subject = CloudLogoutServiceError.missingCloudURL

        // When
        let got = subject.description

        // Then
        XCTAssertEqual(got, "The cloud URL attribute is missing in your project's configuration.")
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
    var configLoader: MockConfigLoader!
    var subject: CloudLogoutService!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionController()
        configLoader = MockConfigLoader()
        subject = CloudLogoutService(
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

    func test_printSession_when_cloudURL_is_missing() {
        // Given
        configLoader.loadConfigStub = { _ in
            Config.test(cloud: nil)
        }

        // Then
        XCTAssertThrowsSpecific(try subject.logout(), CloudLogoutServiceError.missingCloudURL)
    }

    func test_printSession() throws {
        // Given
        let cloudURL = URL.test()
        configLoader.loadConfigStub = { _ in
            Config.test(cloud: Cloud(url: cloudURL, projectId: "123", options: []))
        }

        // When
        try subject.logout()

        // Then
        XCTAssertTrue(cloudSessionController.logoutArgs.contains(cloudURL))
    }
}
