#if os(macOS)
    import Foundation
    import Mockable
    import TuistConfigLoader
    import TuistCore
    import TuistServer
    import XCTest

    @testable import TuistAuthCommand
    @testable import TuistTesting

    final class LogoutServiceTests: TuistUnitTestCase {
        private var serverSessionController: MockServerSessionControlling!
        private var subject: LogoutService!
        private var configLoader: MockConfigLoading!
        private var serverEnvironmentService: MockServerEnvironmentServicing!
        private var serverURL: URL!

        override func setUp() {
            super.setUp()
            serverSessionController = MockServerSessionControlling()
            configLoader = MockConfigLoading()
            serverURL = URL(string: "https://test.tuist.dev")!
            serverEnvironmentService = MockServerEnvironmentServicing()
            given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
            given(serverEnvironmentService).url(configServerURL: .value(serverURL)).willReturn(serverURL)
            subject = LogoutService(
                serverSessionController: serverSessionController,
                serverEnvironmentService: serverEnvironmentService,
                configLoader: configLoader
            )
        }

        override func tearDown() {
            serverSessionController = nil
            serverURL = nil
            configLoader = nil
            serverEnvironmentService = nil
            subject = nil
            super.tearDown()
        }

        func test_logout() async throws {
            // Given
            given(serverSessionController)
                .logout(serverURL: .value(serverURL))
                .willReturn(())

            // When / Then
            try await subject.logout(directory: nil, serverURL: nil)
        }
    }
#endif
