import Foundation
import Mockable
import Testing
import TuistServer

@testable import TuistAuthCommand

struct AuthTokenServiceTests {
    private let serverURL = URL(string: "https://test.tuist.dev")!

    private func subject(
        credential: AuthenticationToken = .project("opaque-project-token"),
        getCacheTokenService: GetCacheTokenServicing = MockGetCacheTokenServicing()
    ) -> AuthTokenService {
        let serverAuthenticationController = MockServerAuthenticationControlling()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any, refreshIfNeeded: .any)
            .willReturn(credential)
        let serverEnvironmentService = MockServerEnvironmentServicing()
        given(serverEnvironmentService).url().willReturn(serverURL)

        return AuthTokenService(
            serverAuthenticationController: serverAuthenticationController,
            serverEnvironmentService: serverEnvironmentService,
            getCacheTokenService: getCacheTokenService
        )
    }

    /// The proxy asks without a project when it does not know one, and must still
    /// get a usable bearer rather than an exchange it did not ask for.
    @Test func returns_the_credential_when_no_project_is_named() async throws {
        // Given
        let getCacheTokenService = MockGetCacheTokenServicing()

        // When
        let token = try await subject(getCacheTokenService: getCacheTokenService)
            .token(serverURL: nil, projectHandle: nil)

        // Then
        #expect(token == "opaque-project-token")
        verify(getCacheTokenService)
            .getCacheToken(serverURL: .any, projectHandle: .any)
            .called(0)
    }

    /// The point of the flag: a cache node cannot verify the CI credential, so
    /// naming the project has to yield one it can.
    @Test func exchanges_for_a_cache_token_when_a_project_is_named() async throws {
        // Given
        let getCacheTokenService = MockGetCacheTokenServicing()
        given(getCacheTokenService)
            .getCacheToken(serverURL: .any, projectHandle: .value("acme/ios"))
            .willReturn(CacheToken(token: "cache-token", expiresIn: 1800))

        // When
        let token = try await subject(getCacheTokenService: getCacheTokenService)
            .token(serverURL: nil, projectHandle: "acme/ios")

        // Then
        #expect(token == "cache-token")
    }

    /// A server that cannot mint one has to leave the caller with the credential
    /// it already had, which cache nodes still accept.
    @Test func falls_back_to_the_credential_when_the_exchange_fails() async throws {
        // Given
        struct UnavailableError: Error {}
        let getCacheTokenService = MockGetCacheTokenServicing()
        given(getCacheTokenService)
            .getCacheToken(serverURL: .any, projectHandle: .any)
            .willThrow(UnavailableError())

        // When
        let token = try await subject(getCacheTokenService: getCacheTokenService)
            .token(serverURL: nil, projectHandle: "acme/ios")

        // Then
        #expect(token == "opaque-project-token")
    }

    @Test func throws_when_there_is_no_credential() async throws {
        // Given
        let serverAuthenticationController = MockServerAuthenticationControlling()
        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any, refreshIfNeeded: .any)
            .willReturn(nil)
        let serverEnvironmentService = MockServerEnvironmentServicing()
        given(serverEnvironmentService).url().willReturn(serverURL)
        let subject = AuthTokenService(
            serverAuthenticationController: serverAuthenticationController,
            serverEnvironmentService: serverEnvironmentService,
            getCacheTokenService: MockGetCacheTokenServicing()
        )

        // When / Then
        await #expect(throws: AuthTokenServiceError.notAuthenticated(serverURL)) {
            try await subject.token(serverURL: nil, projectHandle: "acme/ios")
        }
    }
}
