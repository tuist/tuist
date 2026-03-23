#if os(macOS)
    import Foundation
    import Mockable
    import TuistConfigLoader
    import TuistCore
    import TuistServer
    import Testing

    @testable import TuistAuthCommand
    @testable import TuistTesting

    struct LogoutServiceTests {
        private let serverSessionController: MockServerSessionControlling
        private let subject: LogoutService
        private let configLoader: MockConfigLoading
        private let serverURL: URL
        init() {
            serverSessionController = MockServerSessionControlling()
            configLoader = MockConfigLoading()
            serverURL = URL(string: "https://test.tuist.dev")!
            given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
            subject = LogoutService(
                serverSessionController: serverSessionController,
                configLoader: configLoader
            )
        }


        @Test
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
