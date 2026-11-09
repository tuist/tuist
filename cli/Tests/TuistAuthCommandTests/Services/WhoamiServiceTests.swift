#if os(macOS)
    import Foundation
    import Mockable
    import TuistConfigLoader
    import TuistConstants
    import TuistCore
    import TuistEnvironment
    import TuistEnvironmentTesting
    import TuistServer
    import XCTest
    @testable import TuistAuthCommand
    @testable import TuistTesting

    final class WhoamiServiceTests: TuistUnitTestCase {
        private var serverAuthenticationController: MockServerAuthenticationControlling!
        private var subject: WhoamiService!
        private var configLoader: MockConfigLoading!
        private var serverURL: URL!

        override func setUp() {
            super.setUp()
            serverAuthenticationController = MockServerAuthenticationControlling()
            configLoader = MockConfigLoading()
            serverURL = URL(string: "https://test.tuist.dev")!
            given(configLoader).loadConfig(path: .any).willReturn(.test(url: serverURL))
            subject = WhoamiService(
                serverAuthenticationController: serverAuthenticationController,
                configLoader: configLoader
            )
        }

        override func tearDown() {
            serverAuthenticationController = nil
            configLoader = nil
            serverURL = nil
            subject = nil
            super.tearDown()
        }

        func test_whoami_when_logged_in_as_user_with_username() async throws {
            try await withMockedDependencies {
                // Given
                given(serverAuthenticationController)
                    .authenticationToken(serverURL: .value(serverURL))
                    .willReturn(
                        .user(
                            accessToken: .test(
                                email: "tuist@tuist.dev",
                                preferredUsername: "tuist"
                            ),
                            refreshToken: .test()
                        )
                    )

                // When
                try await subject.run(directory: nil, serverURL: nil)

                // Then
                XCTAssertPrinterOutputContains("tuist")
            }
        }

        func test_whoami_when_logged_in_as_user_with_email() async throws {
            try await withMockedDependencies {
                // Given
                given(serverAuthenticationController)
                    .authenticationToken(serverURL: .value(serverURL))
                    .willReturn(
                        .user(
                            accessToken: .test(
                                email: "tuist@tuist.dev",
                                preferredUsername: nil
                            ),
                            refreshToken: .test()
                        )
                    )

                // When
                try await subject.run(directory: nil, serverURL: nil)

                // Then
                XCTAssertPrinterOutputContains("tuist@tuist.dev")
            }
        }

        func test_whoami_when_logged_in_as_user_without_identity() async throws {
            try await withMockedDependencies {
                // Given
                given(serverAuthenticationController)
                    .authenticationToken(serverURL: .value(serverURL))
                    .willReturn(
                        .user(
                            accessToken: .test(
                                email: nil,
                                preferredUsername: nil
                            ),
                            refreshToken: .test()
                        )
                    )

                // When
                try await subject.run(directory: nil, serverURL: nil)

                // Then
                XCTAssertPrinterOutputContains("Authenticated as user")
            }
        }

        func test_whoami_when_logged_in_with_account_token_carrying_username() async throws {
            try await withMockedDependencies {
                // Given
                given(serverAuthenticationController)
                    .authenticationToken(serverURL: .value(serverURL))
                    .willReturn(
                        .account(
                            .test(
                                email: "tuist@tuist.dev",
                                preferredUsername: "tuist"
                            )
                        )
                    )

                // When
                try await subject.run(directory: nil, serverURL: nil)

                // Then
                XCTAssertPrinterOutputContains("tuist (account token)")
            }
        }

        func test_whoami_when_logged_in_with_account_token_carrying_email() async throws {
            try await withMockedDependencies {
                // Given
                given(serverAuthenticationController)
                    .authenticationToken(serverURL: .value(serverURL))
                    .willReturn(
                        .account(
                            .test(
                                email: "tuist@tuist.dev",
                                preferredUsername: nil
                            )
                        )
                    )

                // When
                try await subject.run(directory: nil, serverURL: nil)

                // Then
                XCTAssertPrinterOutputContains("tuist@tuist.dev (account token)")
            }
        }

        func test_whoami_when_logged_in_with_account_token_without_identity() async throws {
            try await withMockedDependencies {
                // Given
                given(serverAuthenticationController)
                    .authenticationToken(serverURL: .value(serverURL))
                    .willReturn(
                        .account(
                            .test(
                                email: nil,
                                preferredUsername: nil
                            )
                        )
                    )

                // When
                try await subject.run(directory: nil, serverURL: nil)

                // Then
                XCTAssertPrinterOutputContains("Authenticated with an account token")
            }
        }

        func test_whoami_when_logged_in_with_project_token_from_tuist_token() async throws {
            try await withMockedEnvironment {
                try await withMockedDependencies {
                    // Given
                    Environment.mocked?.variables[Constants.EnvironmentVariables.token] = "token"
                    given(serverAuthenticationController)
                        .authenticationToken(serverURL: .value(serverURL))
                        .willReturn(.project("token"))

                    // When
                    try await subject.run(directory: nil, serverURL: nil)

                    // Then
                    XCTAssertPrinterOutputContains("Authenticated with a project token (TUIST_TOKEN)")
                }
            }
        }

        func test_whoami_when_logged_in_with_project_token_without_env_var() async throws {
            try await withMockedEnvironment {
                try await withMockedDependencies {
                    // Given
                    given(serverAuthenticationController)
                        .authenticationToken(serverURL: .value(serverURL))
                        .willReturn(.project("token"))

                    // When
                    try await subject.run(directory: nil, serverURL: nil)

                    // Then
                    XCTAssertPrinterOutputContains("Authenticated with a project token")
                }
            }
        }

        func test_whoami_when_logged_out() async throws {
            try await withMockedDependencies {
                // Given
                given(serverAuthenticationController)
                    .authenticationToken(serverURL: .value(serverURL))
                    .willReturn(nil)

                // When / Then
                await XCTAssertThrowsSpecific(
                    try await subject.run(directory: nil, serverURL: nil),
                    ServerSessionControllerError.unauthenticated
                )
            }
        }
    }
#endif
