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

final class AuthServiceTests: TuistUnitTestCase {
    private var serverSessionController: MockServerSessionControlling!
    private var configLoader: MockConfigLoading!
    private var cloudURL: URL!
    private var subject: AuthService!

    override func setUp() {
        super.setUp()
        serverSessionController = .init()
        configLoader = MockConfigLoading()
        cloudURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(.test(cloud: .test(url: cloudURL)))

        subject = AuthService(
            serverSessionController: serverSessionController,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        serverSessionController = nil
        configLoader = nil
        cloudURL = nil
        subject = nil
        super.tearDown()
    }

    func test_authenticate() async throws {
        // Given
        given(serverSessionController)
            .authenticate(serverURL: .value(cloudURL))
            .willReturn(())

        // When / Then
        try await subject.authenticate(directory: nil)
    }
}
