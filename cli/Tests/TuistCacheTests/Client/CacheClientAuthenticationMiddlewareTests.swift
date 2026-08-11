import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import Testing
import TuistHTTP
import TuistServer

@testable import TuistCache

struct CacheClientAuthenticationMiddlewareTests {
    private var subject: CacheClientAuthenticationMiddleware!
    private var mockServerAuthenticationController: MockServerAuthenticationControlling!
    private var mockCacheTokenStore: MockCacheTokenStoring!

    init() {
        mockServerAuthenticationController = .init()
        mockCacheTokenStore = .init()
        subject = CacheClientAuthenticationMiddleware(
            authenticationURL: URL(string: "https://auth.tuist.dev")!,
            serverAuthenticationController: mockServerAuthenticationController,
            cacheTokenStore: mockCacheTokenStore,
            projectHandle: nil
        )
    }

    private func subject(projectHandle: String?) -> CacheClientAuthenticationMiddleware {
        CacheClientAuthenticationMiddleware(
            authenticationURL: URL(string: "https://auth.tuist.dev")!,
            serverAuthenticationController: mockServerAuthenticationController,
            cacheTokenStore: mockCacheTokenStore,
            projectHandle: projectHandle
        )
    }

    @Test func intercept_throws_notAuthenticated_when_no_token() async throws {
        // Given
        given(mockServerAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(nil)

        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")

        // When / Then
        await #expect(throws: ClientAuthenticationError.notAuthenticated) {
            try await subject.intercept(
                request,
                body: nil,
                baseURL: URL(string: "https://cache.tuist.dev")!,
                operationID: "test"
            ) { _, _, _ in
                (HTTPResponse(status: 200), nil)
            }
        }
    }

    @Test func intercept_adds_authorization_header_when_token_present() async throws {
        // Given
        let token = AuthenticationToken.project("test-auth-token")
        given(mockServerAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(token)

        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        let expectedResponse = HTTPResponse(status: 200)
        var capturedRequest: HTTPRequest!

        // When
        let (response, _) = try await subject.intercept(
            request,
            body: nil,
            baseURL: URL(string: "https://cache.tuist.dev")!,
            operationID: "test"
        ) { request, body, _ in
            capturedRequest = request
            return (expectedResponse, body)
        }

        // Then
        #expect(response == expectedResponse)
        #expect(
            capturedRequest.headerFields ==
                [
                    .authorization: "Bearer test-auth-token",
                ]
        )
    }

    @Test func intercept_uses_authenticationURL_for_token_lookup() async throws {
        // Given
        let authenticationURL = URL(string: "https://auth.tuist.dev")!
        let baseURL = URL(string: "https://cache.tuist.dev")!
        let token = AuthenticationToken.project("auth-token")

        given(mockServerAuthenticationController)
            .authenticationToken(serverURL: .value(authenticationURL))
            .willReturn(token)

        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")

        // When
        _ = try await subject.intercept(
            request,
            body: nil,
            baseURL: baseURL,
            operationID: "test"
        ) { _, body, _ in
            (HTTPResponse(status: 200), body)
        }

        // Then
        verify(mockServerAuthenticationController)
            .authenticationToken(serverURL: .value(authenticationURL))
            .called(1)
    }

    /// Without a project handle there is nothing to scope a cache token to, so
    /// the credential the CLI already holds is sent unchanged.
    @Test func intercept_does_not_exchange_when_project_handle_is_absent() async throws {
        // Given
        given(mockServerAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("opaque-token"))

        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        var capturedRequest: HTTPRequest!

        // When
        _ = try await subject.intercept(
            request,
            body: nil,
            baseURL: URL(string: "https://cache.tuist.dev")!,
            operationID: "test"
        ) { request, body, _ in
            capturedRequest = request
            return (HTTPResponse(status: 200), body)
        }

        // Then
        #expect(capturedRequest.headerFields[.authorization] == "Bearer opaque-token")
        verify(mockCacheTokenStore)
            .cacheToken(authenticationURL: .any, projectHandle: .any)
            .called(0)
    }

    @Test func intercept_sends_the_cache_token_when_one_can_be_minted() async throws {
        // Given
        given(mockServerAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("opaque-token"))
        given(mockCacheTokenStore)
            .cacheToken(authenticationURL: .any, projectHandle: .value("acme/ios"))
            .willReturn("cache-token")

        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        var capturedRequest: HTTPRequest!

        // When
        _ = try await subject(projectHandle: "acme/ios").intercept(
            request,
            body: nil,
            baseURL: URL(string: "https://cache.tuist.dev")!,
            operationID: "test"
        ) { request, body, _ in
            capturedRequest = request
            return (HTTPResponse(status: 200), body)
        }

        // Then
        #expect(capturedRequest.headerFields[.authorization] == "Bearer cache-token")
    }

    /// A server that cannot mint one must not break cache access, since cache
    /// nodes still accept the original credential.
    @Test func intercept_falls_back_to_the_credential_when_the_exchange_fails() async throws {
        // Given
        given(mockServerAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(.project("opaque-token"))
        given(mockCacheTokenStore)
            .cacheToken(authenticationURL: .any, projectHandle: .any)
            .willReturn(nil)

        let request = HTTPRequest(method: .get, scheme: nil, authority: nil, path: "/")
        var capturedRequest: HTTPRequest!

        // When
        _ = try await subject(projectHandle: "acme/ios").intercept(
            request,
            body: nil,
            baseURL: URL(string: "https://cache.tuist.dev")!,
            operationID: "test"
        ) { request, body, _ in
            capturedRequest = request
            return (HTTPResponse(status: 200), body)
        }

        // Then
        #expect(capturedRequest.headerFields[.authorization] == "Bearer opaque-token")
    }
}
