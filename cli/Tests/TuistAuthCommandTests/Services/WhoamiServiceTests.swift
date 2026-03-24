#if os(macOS)
    import Foundation
    import Mockable
    import Testing
    import TuistConfigLoader
    import TuistCore
    import TuistServer

    @testable import TuistAuthCommand
    @testable import TuistTesting

    struct WhoamiServiceTests {
        private let serverSessionController: MockServerSessionControlling
        private let subject: WhoamiService
        private let configLoader: MockConfigLoading
        private let serverURL: URL
        init() {
            serverSessionController = MockServerSessionControlling()
            configLoader = MockConfigLoading()
            serverURL = URL(string: "https://test.tuist.dev")!
            given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
            subject = WhoamiService(
                serverSessionController: serverSessionController,
                configLoader: configLoader
            )
        }

        @Test
        func whoami_when_logged_in() async throws {
            try await withMockedDependencies {
                // Given
                given(serverSessionController)
                    .authenticatedHandle(serverURL: .value(serverURL))
                    .willReturn("tuist@tuist.dev")

                // When
                try await subject.run(directory: nil, serverURL: nil)

                // Then
                TuistTest.expectLogs("tuist@tuist.dev")
            }
        }

        @Test
        func whoami_when_logged_out() async throws {
            try await withMockedDependencies {
                // Given
                given(serverSessionController)
                    .authenticatedHandle(serverURL: .value(serverURL))
                    .willThrow(ServerSessionControllerError.unauthenticated)

                await #expect(throws: ServerSessionControllerError.unauthenticated) { try await subject.run(
                    directory: nil,
                    serverURL: nil
                ) }
            }
        }
    }
#endif
