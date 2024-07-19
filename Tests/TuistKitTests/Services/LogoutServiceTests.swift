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

final class LogoutServiceTests: TuistUnitTestCase {
    private var serverSessionController: MockServerSessionControlling!
    private var subject: LogoutService!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!

    override func setUp() {
        super.setUp()
        serverSessionController = MockServerSessionControlling()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
        subject = LogoutService(
            serverSessionController: serverSessionController,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        serverSessionController = nil
        serverURL = nil
        configLoader = nil
        subject = nil
        super.tearDown()
    }

    func test_logout() async throws {
        // Given
        given(serverSessionController)
            .logout(serverURL: .value(serverURL))
            .willReturn(())

        // When / Then
        try await subject.logout(directory: nil)
    }
}
