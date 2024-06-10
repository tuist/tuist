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

final class CloudSessionServiceTests: TuistUnitTestCase {
    private var cloudSessionController: MockCloudSessionControlling!
    private var subject: CloudSessionService!
    private var configLoader: MockConfigLoading!
    private var cloudURL: URL!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionControlling()
        configLoader = MockConfigLoading()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(cloud: .test(url: cloudURL)))
        subject = CloudSessionService(
            cloudSessionController: cloudSessionController,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        cloudSessionController = nil
        configLoader = nil
        cloudURL = nil
        subject = nil
        super.tearDown()
    }

    func test_printSession() throws {
        // Given
        given(cloudSessionController)
            .printSession(serverURL: .value(cloudURL))
            .willReturn(())

        // When / Then
        try subject.printSession(directory: nil)
    }
}
