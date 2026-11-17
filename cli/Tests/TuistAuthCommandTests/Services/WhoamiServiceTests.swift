#if os(macOS)
    import Foundation
    import Mockable
    import TuistConfigLoader
    import TuistCore
    import TuistServer
    import XCTest

    @testable import TuistAuthCommand
    @testable import TuistTesting

    final class WhoamiServiceTests: TuistUnitTestCase {
        private var serverSessionController: MockServerSessionControlling!
        private var subject: WhoamiService!
        private var configLoader: MockConfigLoading!
        private var serverEnvironmentService: MockServerEnvironmentServicing!
        private var serverURL: URL!
        private var output: [String] = []

        override func setUp() {
            super.setUp()
            serverSessionController = MockServerSessionControlling()
            configLoader = MockConfigLoading()
            serverURL = URL(string: "https://test.tuist.dev")!
            serverEnvironmentService = MockServerEnvironmentServicing()
            given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
            given(serverEnvironmentService).url(configServerURL: .value(serverURL)).willReturn(serverURL)
            subject = WhoamiService(
                serverSessionController: serverSessionController,
                serverEnvironmentService: serverEnvironmentService,
                configLoader: configLoader,
                write: { [unowned self] in output.append($0) }
            )
        }

        override func tearDown() {
            serverSessionController = nil
            configLoader = nil
            serverEnvironmentService = nil
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
                try await subject.run(directory: nil, serverURL: nil)

                // Then
                XCTAssertEqual(output, ["tuist@tuist.dev"])
            }
        }

        func test_whoami_when_logged_out() async throws {
            try await withMockedDependencies {
                // Given
                given(serverSessionController)
                    .authenticatedHandle(serverURL: .value(serverURL))
                    .willThrow(ServerSessionControllerError.unauthenticated)

                await XCTAssertThrowsSpecific(
                    try await subject.run(directory: nil, serverURL: nil), ServerSessionControllerError.unauthenticated
                )
            }
        }
    }
#endif
