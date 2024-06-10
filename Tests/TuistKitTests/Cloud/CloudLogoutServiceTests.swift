import Foundation
import MockableTest
import Path
import TuistCore
import TuistCoreTesting
import TuistLoader
import TuistLoaderTesting
import TuistServer
import TuistSupport
import XcodeGraph
import XcodeGraphTesting
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class CloudLogoutServiceTests: TuistUnitTestCase {
    private var cloudSessionController: MockCloudSessionControlling!
    private var subject: CloudLogoutService!
    private var configLoader: MockConfigLoading!
    private var cloudURL: URL!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionControlling()
        configLoader = MockConfigLoading()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(cloud: .test(url: cloudURL)))
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
