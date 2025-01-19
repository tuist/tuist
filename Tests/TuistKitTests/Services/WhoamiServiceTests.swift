import Foundation
import Mockable
import ServiceContextModule
import TuistCore
import TuistCoreTesting
import TuistLoader
import TuistLoaderTesting
import TuistServer
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

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
        try await ServiceContext.withTestingDependencies {
            // Given
            given(serverSessionController)
                .authenticatedHandle(serverURL: .value(serverURL))
                .willReturn("tuist@tuist.io")

            // When
            try await subject.run(directory: nil)

            // Then
            XCTAssertPrinterOutputContains("tuist@tuist.io")
        }
    }

    func test_whoami_when_logged_out() async throws {
        try await ServiceContext.withTestingDependencies {
            // Given
            given(serverSessionController)
                .authenticatedHandle(serverURL: .value(serverURL))
                .willThrow(ServerSessionControllerError.unauthenticated)

            await XCTAssertThrowsSpecific(try await subject.run(directory: nil), ServerSessionControllerError.unauthenticated)
        }
    }
}
