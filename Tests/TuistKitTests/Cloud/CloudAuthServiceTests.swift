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
import XCTest
@testable import TuistKit
@testable import TuistSupportTesting

final class CloudAuthServiceTests: TuistUnitTestCase {
    private var cloudSessionController: MockCloudSessionControlling!
    private var configLoader: MockConfigLoading!
    private var cloudURL: URL!
    private var subject: CloudAuthService!

    override func setUp() {
        super.setUp()
        cloudSessionController = .init()
        configLoader = MockConfigLoading()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(cloud: .test(url: cloudURL)))

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
