import Foundation
import Mockable
import Testing
import TuistServer

@testable import TuistCAS

struct ServerCacheAuthenticationAdapterTests {
    private var subject: ServerCacheAuthenticationAdapter!
    private var mockServerAuthController: MockServerAuthenticationControlling!

    init() {
        mockServerAuthController = .init()
        subject = ServerCacheAuthenticationAdapter(
            serverAuthenticationController: mockServerAuthController
        )
    }

    @Test func authenticationToken_returns_token_value_when_user_token_present() async throws {
        // Given
        let serverURL = URL(string: "https://api.tuist.dev")!
        let token: AuthenticationToken = .user(
            accessToken: .test(token: "user-access-token"),
            refreshToken: .test(token: "user-refresh-token")
        )

        given(mockServerAuthController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(token)

        // When
        let result = try await subject.authenticationToken(serverURL: serverURL)

        // Then
        #expect(result == "user-access-token")
    }

    @Test func authenticationToken_returns_token_value_when_project_token_present() async throws {
        // Given
        let serverURL = URL(string: "https://api.tuist.dev")!
        let token: AuthenticationToken = .project("project-token-value")

        given(mockServerAuthController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(token)

        // When
        let result = try await subject.authenticationToken(serverURL: serverURL)

        // Then
        #expect(result == "project-token-value")
    }

    @Test func authenticationToken_returns_token_value_when_account_token_present() async throws {
        // Given
        let serverURL = URL(string: "https://api.tuist.dev")!
        let token: AuthenticationToken = .account(.test(token: "account-access-token"))

        given(mockServerAuthController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(token)

        // When
        let result = try await subject.authenticationToken(serverURL: serverURL)

        // Then
        #expect(result == "account-access-token")
    }

    @Test func authenticationToken_returns_nil_when_no_token() async throws {
        // Given
        let serverURL = URL(string: "https://api.tuist.dev")!

        given(mockServerAuthController)
            .authenticationToken(serverURL: .value(serverURL))
            .willReturn(nil)

        // When
        let result = try await subject.authenticationToken(serverURL: serverURL)

        // Then
        #expect(result == nil)
    }

    @Test func authenticationToken_propagates_errors() async throws {
        // Given
        let serverURL = URL(string: "https://api.tuist.dev")!
        let expectedError = ServerAuthenticationControllerError.timedOut(seconds: 30, serverURL: serverURL)

        given(mockServerAuthController)
            .authenticationToken(serverURL: .value(serverURL))
            .willThrow(expectedError)

        // When / Then
        await #expect(throws: ServerAuthenticationControllerError.self) {
            _ = try await subject.authenticationToken(serverURL: serverURL)
        }
    }
}
