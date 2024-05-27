import Foundation
import MockableTest
import TSCBasic
import TuistServer
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
    private var cloudSessionController: MockCloudSessionControlling!
    private var subject: CloudLogoutService!
    private var configLoader: MockConfigLoader!
    private var cloudURL: URL!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionControlling()
        configLoader = MockConfigLoader()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        configLoader.loadConfigStub = { _ in Config.test(cloud: .test(url: self.cloudURL)) }
        subject = CloudLogoutService(
            cloudSessionController: cloudSessionController,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        cloudSessionController = nil
        cloudURL = nil
        configLoader = nil
        subject = nil
        super.tearDown()
    }

    func test_logout() throws {
        // Given
        given(cloudSessionController)
            .logout(serverURL: .value(cloudURL))
            .willReturn(())

        // When / Then
        try subject.logout(directory: nil)
    }
}
