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

final class CloudAuthServiceTests: TuistUnitTestCase {
    private var cloudSessionController: MockCloudSessionControlling!
    private var configLoader: MockConfigLoader!
    private var cloudURL: URL!
    private var subject: CloudAuthService!

    override func setUp() {
        super.setUp()
        cloudSessionController = .init()
        configLoader = MockConfigLoader()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        configLoader.loadConfigStub = { _ in Config.test(cloud: .test(url: self.cloudURL)) }

        subject = CloudAuthService(
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

    func test_authenticate() async throws {
        // Given
        given(cloudSessionController)
            .authenticate(serverURL: .value(cloudURL))
            .willReturn(())

        // When / Then
        try await subject.authenticate(directory: nil)
    }
}
