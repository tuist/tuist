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

final class SessionServiceTests: TuistUnitTestCase {
    private var serverSessionController: MockServerSessionControlling!
    private var subject: SessionService!
    private var configLoader: MockConfigLoading!
    private var serverURL: URL!

    override func setUp() {
        super.setUp()
        serverSessionController = MockServerSessionControlling()
        configLoader = MockConfigLoading()
        serverURL = URL(string: "https://test.cloud.tuist.io")!
        given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
        subject = SessionService(
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

    func test_printSession() async throws {
        // Given
        given(serverSessionController)
            .printSession(serverURL: .value(serverURL))
            .willReturn(())

        // When / Then
        try await subject.printSession(directory: nil)
    }
}
