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

final class CloudLogoutServiceTests: TuistUnitTestCase {
    private var cloudSessionController: MockCloudSessionController!
    private var subject: CloudLogoutService!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionController()
        subject = CloudLogoutService(
            cloudSessionController: cloudSessionController
        )
    }

    override func tearDown() {
        cloudSessionController = nil
        subject = nil
        super.tearDown()
    }

    func test_logout() throws {
        // When
        try subject.logout(serverURL: nil)

        // Then
        XCTAssertTrue(cloudSessionController.logoutArgs.contains(URL(string: Constants.tuistCloudURL)!))
    }
}
