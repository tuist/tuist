import Foundation
import MockableTest
import TSCBasic
import TuistApp
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

final class CloudSessionServiceTests: TuistUnitTestCase {
    private var cloudSessionController: MockCloudSessionControlling!
    private var subject: CloudSessionService!
    private var configLoader: MockConfigLoader!
    private var cloudURL: URL!

    override func setUp() {
        super.setUp()
        cloudSessionController = MockCloudSessionControlling()
        configLoader = MockConfigLoader()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        configLoader.loadConfigStub = { _ in Config.test(cloud: .test(url: self.cloudURL)) }
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
