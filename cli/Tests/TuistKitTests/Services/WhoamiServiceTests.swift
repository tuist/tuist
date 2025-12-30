import Foundation
import Mockable
import TuistCore
import TuistLoader
import TuistServer
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistTesting

final class WhoamiServiceTests: TuistUnitTestCase {
    private var serverSessionController: MockServerSessionControlling!
    private var subject: WhoamiService!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!

    override func setUp() {
        super.setUp()
        serverSessionController = MockServerSessionControlling()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.tuist.dev")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
        subject = WhoamiService(
            serverSessionController: serverSessionController,
            configLoader: configLoader
        )
    }

    override func tearDown() {
        serverSessionController = nil
        configLoader = nil
        serverURL = nil
        subject = nil
        super.tearDown()
    }

    func test_whoami_when_logged_in() async throws {
        try await withMockedDependencies {
            // Given
            given(serverSessionController)
                .authenticatedHandle(serverURL: .value(serverURL))
                .willReturn("tuist@tuist.dev")

            // When
            try await subject.run(directory: nil)

            // Then
            XCTAssertPrinterOutputContains("tuist@tuist.dev")
        }
    }

    func test_whoami_when_logged_out() async throws {
        try await withMockedDependencies {
            // Given
            given(serverSessionController)
                .authenticatedHandle(serverURL: .value(serverURL))
                .willThrow(ServerSessionControllerError.unauthenticated)

            await XCTAssertThrowsSpecific(
                try await subject.run(directory: nil), ServerSessionControllerError.unauthenticated
            )
        }
    }
}
