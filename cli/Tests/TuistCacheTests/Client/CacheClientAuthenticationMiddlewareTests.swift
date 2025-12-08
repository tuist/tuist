import Foundation
import HTTPTypes
import Mockable
import OpenAPIRuntime
import Testing
import TuistSupport

@testable import TuistCache

struct CacheClientAuthenticationMiddlewareTests {
    private var subject: CacheClientAuthenticationMiddleware!
    private var mockAuthProvider: MockCacheAuthenticationProviding!

    init() {
        mockAuthProvider = .init()
        subject = CacheClientAuthenticationMiddleware(
            authenticationURL: URL(string: "https://auth.tuist.dev")!,
            authenticationProvider: mockAuthProvider
        )
    }

    @Test func intercept_throws_notAuthenticated_when_no_token() async throws {
        // Given
        given(mockAuthProvider)
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
        let token = "test-auth-token"
        given(mockAuthProvider)
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
        let token = "auth-token"

        given(mockAuthProvider)
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
        verify(mockAuthProvider)
            .authenticationToken(serverURL: .value(authenticationURL))
            .called(1)
    }
}
