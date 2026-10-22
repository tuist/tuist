import Foundation
import Mockable
import Testing
import TuistServer

@testable import TuistCache

struct CacheCredentialProviderTests {
    private let authenticationURL = URL(string: "https://tuist.dev")!
    private let serverAuthenticationController = MockServerAuthenticationControlling()
    private let cacheTokenStore = MockCacheTokenStoring()

    private func subject(fullHandle: String?) -> CacheCredentialProvider {
        CacheCredentialProvider(
            authenticationURL: authenticationURL,
            fullHandle: fullHandle,
            serverAuthenticationController: serverAuthenticationController,
            cacheTokenStore: cacheTokenStore
        )
    }

    @Test func returns_the_token_exchanged_for_the_project() async throws {
        given(serverAuthenticationController).authenticationToken(serverURL: .value(authenticationURL))
            .willReturn(.project("opaque-token"))
        given(cacheTokenStore).cacheToken(authenticationURL: .value(authenticationURL), fullHandle: .value("acme/ios"))
            .willReturn("cache-token")

        let credential = try await subject(fullHandle: "acme/ios").credential()

        #expect(credential == "cache-token")
    }

    @Test func returns_the_credential_when_the_exchange_is_unavailable() async throws {
        given(serverAuthenticationController).authenticationToken(serverURL: .any)
            .willReturn(.project("opaque-token"))
        given(cacheTokenStore).cacheToken(authenticationURL: .any, fullHandle: .any)
            .willReturn(nil)

        let credential = try await subject(fullHandle: "acme/ios").credential()

        #expect(credential == "opaque-token")
    }

    @Test func returns_the_credential_without_exchanging_when_the_project_is_unknown() async throws {
        given(serverAuthenticationController).authenticationToken(serverURL: .any)
            .willReturn(.project("opaque-token"))

        let credential = try await subject(fullHandle: nil).credential()

        #expect(credential == "opaque-token")
        verify(cacheTokenStore).cacheToken(authenticationURL: .any, fullHandle: .any).called(0)
    }

    @Test func does_not_send_the_credential_when_the_free_tier_is_exhausted() async throws {
        given(serverAuthenticationController).authenticationToken(serverURL: .any)
            .willReturn(.project("opaque-token"))
        given(cacheTokenStore).cacheToken(authenticationURL: .any, fullHandle: .any)
            .willThrow(GetCacheTokenServiceError.freeTierExhausted("Upgrade your plan."))

        await #expect(throws: GetCacheTokenServiceError.freeTierExhausted("Upgrade your plan.")) {
            try await subject(fullHandle: "acme/ios").credential()
        }
    }

    @Test func returns_nil_without_a_credential() async throws {
        given(serverAuthenticationController).authenticationToken(serverURL: .any)
            .willReturn(nil)

        let credential = try await subject(fullHandle: "acme/ios").credential()

        #expect(credential == nil)
        verify(cacheTokenStore).cacheToken(authenticationURL: .any, fullHandle: .any).called(0)
    }
}
