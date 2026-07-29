import Foundation
import Mockable
import Testing
import TuistConfig
import TuistConfigLoader
import TuistEnvironment
import TuistEnvironmentTesting
import TuistServer
import TuistTesting

@testable import TuistBazelCommand

struct BazelCredentialHelperCommandServiceTests {
    private let serverURL = URL(string: "https://test.tuist.dev")!

    private struct RefreshError: Error {}

    private func makeSubject(
        date: @escaping () -> Date = { Date() }
    ) -> (
        subject: BazelCredentialHelperCommandService,
        serverAuthenticationController: MockServerAuthenticationControlling
    ) {
        let serverEnvironmentService = MockServerEnvironmentServicing()
        let serverAuthenticationController = MockServerAuthenticationControlling()
        let configLoader = MockConfigLoading()

        given(configLoader)
            .loadConfig(path: .any)
            .willReturn(Tuist.test(url: serverURL))

        given(serverEnvironmentService)
            .url(configServerURL: .any)
            .willReturn(serverURL)

        let subject = BazelCredentialHelperCommandService(
            serverEnvironmentService: serverEnvironmentService,
            serverAuthenticationController: serverAuthenticationController,
            configLoader: configLoader,
            date: date
        )

        return (subject, serverAuthenticationController)
    }

    @Test(.withMockedEnvironment())
    func credentials_returns_authorization_header_and_expiry_for_user_tokens() async throws {
        // Given
        let (subject, serverAuthenticationController) = makeSubject(
            date: { Date(timeIntervalSince1970: 1_750_000_000 - 3600) }
        )
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                .user(
                    accessToken: .test(
                        token: "access-token",
                        expiryDate: Date(timeIntervalSince1970: 1_750_000_000)
                    ),
                    refreshToken: .test(token: "refresh-token")
                )
            )

        // When
        let response = try await subject.credentials(helperCommand: "get", directory: nil)

        // Then
        // The reported expiry is brought forward by the 60s safety margin so Bazel
        // re-invokes the helper before the token is actually rejected by the server.
        #expect(
            response == BazelCredentialHelperResponse(
                headers: ["Authorization": ["Bearer access-token"]],
                expires: "2025-06-15T15:05:40Z"
            )
        )
        verify(serverAuthenticationController)
            .refreshToken(serverURL: .value(serverURL))
            .called(0)
    }

    @Test(.withMockedEnvironment())
    func credentials_refreshes_user_token_within_safety_margin() async throws {
        // Given
        let (subject, serverAuthenticationController) = makeSubject(
            date: { Date(timeIntervalSince1970: 1_750_000_000 - 10) }
        )
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                .user(
                    accessToken: .test(
                        token: "access-token",
                        expiryDate: Date(timeIntervalSince1970: 1_750_000_000)
                    ),
                    refreshToken: .test(token: "refresh-token")
                )
            )
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                .user(
                    accessToken: .test(
                        token: "fresh-access-token",
                        expiryDate: Date(timeIntervalSince1970: 1_750_000_600)
                    ),
                    refreshToken: .test(token: "fresh-refresh-token")
                )
            )
        given(serverAuthenticationController)
            .refreshToken(serverURL: .value(serverURL))
            .willReturn()

        // When
        let response = try await subject.credentials(helperCommand: "get", directory: nil)

        // Then
        #expect(
            response == BazelCredentialHelperResponse(
                headers: ["Authorization": ["Bearer fresh-access-token"]],
                expires: "2025-06-15T15:15:40Z"
            )
        )
        verify(serverAuthenticationController)
            .refreshToken(serverURL: .value(serverURL))
            .called(1)
    }

    @Test(.withMockedEnvironment())
    func credentials_falls_back_to_current_token_when_proactive_refresh_fails() async throws {
        // Given
        let (subject, serverAuthenticationController) = makeSubject(
            date: { Date(timeIntervalSince1970: 1_750_000_000 - 10) }
        )
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                .user(
                    accessToken: .test(
                        token: "access-token",
                        expiryDate: Date(timeIntervalSince1970: 1_750_000_000)
                    ),
                    refreshToken: .test(token: "refresh-token")
                )
            )
        given(serverAuthenticationController)
            .refreshToken(serverURL: .value(serverURL))
            .willThrow(RefreshError())

        // When
        let response = try await subject.credentials(helperCommand: "get", directory: nil)

        // Then
        #expect(
            response == BazelCredentialHelperResponse(
                headers: ["Authorization": ["Bearer access-token"]],
                expires: "2025-06-15T15:05:40Z"
            )
        )
    }

    @Test(.withMockedEnvironment())
    func credentials_returns_no_expiry_for_project_tokens() async throws {
        // Given
        let (subject, serverAuthenticationController) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(.project("project-token"))

        // When
        let response = try await subject.credentials(helperCommand: "get", directory: nil)

        // Then
        #expect(
            response == BazelCredentialHelperResponse(
                headers: ["Authorization": ["Bearer project-token"]],
                expires: nil
            )
        )
    }

    @Test(.withMockedEnvironment())
    func credentials_returns_expiry_for_account_tokens() async throws {
        // Given
        let (subject, serverAuthenticationController) = makeSubject(
            date: { Date(timeIntervalSince1970: 1_750_000_000 - 3600) }
        )
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(
                .account(
                    .test(
                        token: "account-token",
                        expiryDate: Date(timeIntervalSince1970: 1_750_000_000)
                    )
                )
            )

        // When
        let response = try await subject.credentials(helperCommand: "get", directory: nil)

        // Then
        // Account tokens cannot be refreshed, so their exact expiry is reported unchanged.
        #expect(
            response == BazelCredentialHelperResponse(
                headers: ["Authorization": ["Bearer account-token"]],
                expires: "2025-06-15T15:06:40Z"
            )
        )
    }

    @Test(.withMockedEnvironment())
    func credentials_throws_when_the_command_is_not_get() async throws {
        // Given
        let (subject, _) = makeSubject()

        // When/Then
        await #expect(throws: BazelCredentialHelperCommandServiceError.unsupportedCommand("store")) {
            try await subject.credentials(helperCommand: "store", directory: nil)
        }
    }

    @Test(.withMockedEnvironment())
    func credentials_throws_when_not_authenticated() async throws {
        // Given
        let (subject, serverAuthenticationController) = makeSubject()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(nil)

        // When/Then
        await #expect(throws: BazelCredentialHelperCommandServiceError.notAuthenticated) {
            try await subject.credentials(helperCommand: "get", directory: nil)
        }
    }
}
