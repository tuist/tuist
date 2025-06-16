import Foundation
import Mockable
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistTesting

final class LogoutServiceTests: TuistUnitTestCase {
    private var serverSessionController: MockServerSessionControlling!
    private var subject: LogoutService!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!

    override func setUp() {
        super.setUp()
        serverSessionController = MockServerSessionControlling()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.tuist.dev")!
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
